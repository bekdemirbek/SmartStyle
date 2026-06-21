import axios from "axios";
import FormData from "form-data";
import {randomUUID} from "crypto";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {onObjectFinalized} from "firebase-functions/v2/storage";
export {generateOutfitSuggestions} from "./generateOutfitSuggestions.js";
export {generatePurchaseSuggestions} from "./generatePurchaseSuggestions.js";
export {generateWardrobeInsight} from "./generateWardrobeInsight.js";
export {analyzeClothingColor} from "./analyzeClothingColor.js";

initializeApp();

setGlobalOptions({maxInstances: 10});

const photoroomApiKey = defineSecret("PHOTOROOM_API_KEY");
const RAW_UPLOADS_PREFIX = "raw_uploads/";
const PROCESSED_PREFIX = "processed/";

const db = getFirestore();

/**
 * Builds the destination PNG path for a raw upload.
 *
 * @param {string} objectName The uploaded object name.
 * @return {string} The processed PNG object path.
 */
function getProcessedPath(objectName: string): string {
  const rawRelativePath = objectName.substring(RAW_UPLOADS_PREFIX.length);
  const withoutExtension = rawRelativePath.replace(/\.[^/.]+$/, "");

  return `${PROCESSED_PREFIX}${withoutExtension}.png`;
}

/**
 * Resolves the Firestore document that should receive processing status.
 *
 * @param {string} objectName The uploaded object name.
 * @param {Object.<string, string>} [metadata] Optional Storage metadata.
 * @return {string} The Firestore document path.
 */
function getFirestoreDocumentPath(
  objectName: string,
  metadata?: { [key: string]: string },
): string {
  if (metadata?.firestorePath) {
    return metadata.firestorePath;
  }

  if (metadata?.collection && metadata?.documentId) {
    return `${metadata.collection}/${metadata.documentId}`;
  }

  const rawRelativePath = objectName.substring(RAW_UPLOADS_PREFIX.length);
  const firstPathPart = rawRelativePath.split("/")[0];
  const documentId = firstPathPart.replace(/\.[^/.]+$/, "");

  return `uploads/${documentId}`;
}

/**
 * Builds a Firebase Storage token download URL for the processed image.
 *
 * @param {string} bucketName The Storage bucket name.
 * @param {string} filePath The processed object path.
 * @param {string} token The Firebase Storage download token.
 * @return {string} The public token download URL.
 */
function getDownloadUrl(bucketName: string, filePath: string, token: string) {
  const encodedPath = encodeURIComponent(filePath);

  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}` +
    `/o/${encodedPath}?alt=media&token=${token}`;
}

export const removeBackground = onObjectFinalized(
  {
    secrets: [photoroomApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const object = event.data;
    const objectName = object.name;
    const bucketName = object.bucket;

    if (!objectName || !bucketName) {
      logger.warn("Storage object is missing name or bucket.", {object});
      return;
    }

    if (!objectName.startsWith(RAW_UPLOADS_PREFIX)) {
      logger.info("Skipping file outside raw_uploads folder.", {objectName});
      return;
    }

    if (!object.contentType?.startsWith("image/")) {
      logger.info("Skipping non-image file.", {
        objectName,
        contentType: object.contentType,
      });
      return;
    }

    const bucket = getStorage().bucket(bucketName);
    const sourceFile = bucket.file(objectName);
    const processedPath = getProcessedPath(objectName);
    const processedFile = bucket.file(processedPath);
    const firestoreDocumentPath = getFirestoreDocumentPath(
      objectName,
      object.metadata,
    );

    try {
      const [imageBuffer] = await sourceFile.download();
      const formData = new FormData();

      formData.append("image_file", imageBuffer, {
        filename: objectName.split("/").pop() ?? "image.jpg",
        contentType: object.contentType,
      });

      const response = await axios.post<ArrayBuffer>(
        "https://sdk.photoroom.com/v1/segment",
        formData,
        {
          headers: {
            ...formData.getHeaders(),
            "x-api-key": photoroomApiKey.value(),
          },
          responseType: "arraybuffer",
          maxBodyLength: Infinity,
          maxContentLength: Infinity,
        },
      );

      const downloadToken = randomUUID();

      await processedFile.save(Buffer.from(response.data), {
        contentType: "image/png",
        resumable: false,
        metadata: {
          cacheControl: "public, max-age=31536000",
          metadata: {
            firebaseStorageDownloadTokens: downloadToken,
            sourceObject: objectName,
          },
        },
      });

      await db.doc(firestoreDocumentPath).set(
        {
          status: "done",
          processedImageUrl: getDownloadUrl(
            bucketName,
            processedPath,
            downloadToken,
          ),
        },
        {merge: true},
      );

      logger.info("Background removed and Firestore updated.", {
        objectName,
        processedPath,
        firestoreDocumentPath,
      });
    } catch (error) {
      logger.error("Failed to remove image background.", {
        objectName,
        firestoreDocumentPath,
        error,
      });
      throw error;
    }
  },
);
