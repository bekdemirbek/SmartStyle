import axios, {isAxiosError} from "axios";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const GEMINI_MODEL_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/" +
  "gemini-2.5-flash-lite:generateContent";
const GEMINI_TIMEOUT_MS = 30000;

type JsonObject = Record<string, unknown>;

const allowedColors = [
  "Siyah",
  "Beyaz",
  "Gri",
  "Bej",
  "Krem",
  "Kahverengi",
  "Lacivert",
  "Mavi",
  "Yeşil",
  "Kırmızı",
  "Bordo",
  "Pembe",
  "Mor",
  "Sarı",
  "Turuncu",
  "Haki",
  "Mint",
  "Nude",
  "Vizon",
  "Füme",
  "Altın",
  "Gümüş",
  "Siyah-Beyaz",
  "Lacivert-Beyaz",
  "Mavi-Beyaz",
  "Gri-Siyah",
  "Bej-Kahverengi",
  "Kırmızı-Beyaz",
  "Yeşil-Beyaz",
  "Pembe-Beyaz",
  "Çok Renkli",
];

/**
 * Analyzes the dominant clothing color from an uploaded image.
 */
export const analyzeClothingColor = onRequest(
  {
    secrets: [geminiApiKey],
    timeoutSeconds: 60,
    memory: "512MiB",
    cors: true,
  },
  async (request, response) => {
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }

    if (request.method !== "POST") {
      response.status(405).json({
        success: false,
        error: "Only POST requests are supported.",
      });
      return;
    }

    try {
      const body = validateRequestBody(request.body);
      const rawText = await callGeminiColorAnalysis(body, geminiApiKey.value());
      const parsed = parseJsonObject(rawText);
      const color = normalizeColor(parsed.color);
      const confidence = normalizeConfidence(parsed.confidence);
      const note = typeof parsed.note === "string" ? parsed.note.trim() : "";

      response.status(200).json({
        success: true,
        data: {
          color,
          confidence,
          note: note || `${color} ana renk olarak tahmin edildi.`,
        },
      });
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.statusCode : 500;
      const message = error instanceof Error ?
        error.message :
        "Unknown server error.";

      logger.error("Color analysis failed.", {error});

      response.status(statusCode).json({
        success: false,
        error: message,
      });
    }
  },
);

interface ColorAnalysisBody {
  imageBase64: string;
  mimeType: string;
  category?: string;
  type?: string;
}

/**
 * Validates request body.
 *
 * @param {unknown} value Request body.
 * @return {ColorAnalysisBody} Validated body.
 */
function validateRequestBody(value: unknown): ColorAnalysisBody {
  if (!isObject(value)) {
    throw new HttpError(400, "Request body must be a JSON object.");
  }

  if (!isNonEmptyString(value.imageBase64)) {
    throw new HttpError(400, "imageBase64 is required.");
  }

  const mimeType = isNonEmptyString(value.mimeType) ?
    value.mimeType :
    "image/jpeg";

  if (!mimeType.startsWith("image/")) {
    throw new HttpError(400, "mimeType must be an image type.");
  }

  return {
    imageBase64: stripDataUrlPrefix(value.imageBase64),
    mimeType,
    category: isNonEmptyString(value.category) ? value.category : undefined,
    type: isNonEmptyString(value.type) ? value.type : undefined,
  };
}

/**
 * Calls Gemini with inline image data.
 *
 * @param {ColorAnalysisBody} body Valid request body.
 * @param {string} apiKey Gemini API key.
 * @return {Promise<string>} Raw model text.
 */
async function callGeminiColorAnalysis(
  body: ColorAnalysisBody,
  apiKey: string,
): Promise<string> {
  if (!apiKey) {
    throw new HttpError(500, "GEMINI_API_KEY secret is not configured.");
  }

  const prompt = [
    "SmartStyle icin kiyafet rengi analiz ediyorsun.",
    "Gorseldeki ana kiyafet parcasinin baskin rengini sec.",
    "Arka plan, golge, askilik ve ten rengini dikkate alma.",
    `Kategori: ${body.category ?? "Belirtilmedi"}`,
    `Tur: ${body.type ?? "Belirtilmedi"}`,
    `Sadece su renklerden birini sec: ${allowedColors.join(", ")}`,
    "Cevabi sadece JSON olarak ver:",
    "{\"color\":\"Siyah\",\"confidence\":0.85,\"note\":\"Kisa Turkce aciklama\"}",
  ].join("\n");

  try {
    const result = await axios.post(
      `${GEMINI_MODEL_URL}?key=${encodeURIComponent(apiKey)}`,
      {
        contents: [
          {
            role: "user",
            parts: [
              {text: prompt},
              {
                inline_data: {
                  mime_type: body.mimeType,
                  data: body.imageBase64,
                },
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          topP: 0.8,
          maxOutputTokens: 256,
          responseMimeType: "application/json",
        },
      },
      {
        timeout: GEMINI_TIMEOUT_MS,
        headers: {"Content-Type": "application/json"},
      },
    );

    const text = result.data?.candidates?.[0]?.content?.parts
      ?.map((part: JsonObject) => part.text)
      ?.filter((part: unknown) => typeof part === "string")
      ?.join("");

    if (!isNonEmptyString(text)) {
      throw new HttpError(502, "Gemini returned an empty response.");
    }

    return text;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (isAxiosError(error) && error.response?.status === 429) {
      throw new HttpError(
        429,
        "Gemini kotası doldu. Rengi manuel seçebilirsin.",
      );
    }

    logger.error("Gemini color API request failed.", {
      detail: isAxiosError(error) ? error.response?.data ?? error.message : error,
    });
    throw new HttpError(
      502,
      "Renk analizi yapılamadı. Rengi manuel seçebilirsin.",
    );
  }
}

/**
 * Parses a JSON object response.
 *
 * @param {string} text Raw model text.
 * @return {JsonObject} Parsed object.
 */
function parseJsonObject(text: string): JsonObject {
  const cleaned = text
    .trim()
    .replace(/^```(?:json)?/i, "")
    .replace(/```$/i, "")
    .trim();

  const parsed = JSON.parse(cleaned);
  if (!isObject(parsed)) {
    throw new HttpError(502, "Gemini color response must be an object.");
  }
  return parsed;
}

/**
 * Normalizes Gemini color output to the app palette.
 *
 * @param {unknown} value Color value.
 * @return {string} Allowed app color.
 */
function normalizeColor(value: unknown): string {
  if (!isNonEmptyString(value)) return "Çok Renkli";

  const normalized = normalizeText(value);
  for (const color of allowedColors) {
    if (normalizeText(color) === normalized) return color;
  }

  if (hasAll(normalized, ["black", "white"]) ||
      hasAll(normalized, ["siyah", "beyaz"])) {
    return "Siyah-Beyaz";
  }
  if (hasAll(normalized, ["navy", "white"]) ||
      hasAll(normalized, ["lacivert", "beyaz"])) {
    return "Lacivert-Beyaz";
  }
  if (hasAll(normalized, ["blue", "white"]) ||
      hasAll(normalized, ["mavi", "beyaz"])) {
    return "Mavi-Beyaz";
  }
  if ((hasAll(normalized, ["gray", "black"]) ||
      hasAll(normalized, ["grey", "black"]) ||
      hasAll(normalized, ["gri", "siyah"]))) {
    return "Gri-Siyah";
  }
  if (hasAll(normalized, ["beige", "brown"]) ||
      hasAll(normalized, ["bej", "kahverengi"])) {
    return "Bej-Kahverengi";
  }
  if (hasAll(normalized, ["red", "white"]) ||
      hasAll(normalized, ["kirmizi", "beyaz"])) {
    return "Kırmızı-Beyaz";
  }
  if (hasAll(normalized, ["green", "white"]) ||
      hasAll(normalized, ["yesil", "beyaz"])) {
    return "Yeşil-Beyaz";
  }
  if (hasAll(normalized, ["pink", "white"]) ||
      hasAll(normalized, ["pembe", "beyaz"])) {
    return "Pembe-Beyaz";
  }

  if (normalized.includes("black")) return "Siyah";
  if (normalized.includes("white")) return "Beyaz";
  if (normalized.includes("gray") || normalized.includes("grey")) return "Gri";
  if (normalized.includes("navy")) return "Lacivert";
  if (normalized.includes("blue")) return "Mavi";
  if (normalized.includes("green")) return "Yeşil";
  if (normalized.includes("red")) return "Kırmızı";
  if (normalized.includes("brown")) return "Kahverengi";
  if (normalized.includes("beige")) return "Bej";
  if (normalized.includes("cream")) return "Krem";
  if (normalized.includes("pink")) return "Pembe";
  if (normalized.includes("purple")) return "Mor";
  if (normalized.includes("yellow")) return "Sarı";
  if (normalized.includes("orange")) return "Turuncu";
  if (normalized.includes("khaki") || normalized.includes("haki")) return "Haki";
  if (normalized.includes("mint")) return "Mint";
  if (normalized.includes("nude")) return "Nude";
  if (normalized.includes("taupe") || normalized.includes("vizon")) return "Vizon";
  if (normalized.includes("charcoal") || normalized.includes("fume")) return "Füme";
  if (normalized.includes("gold") || normalized.includes("altin")) return "Altın";
  if (normalized.includes("silver") || normalized.includes("gumus")) return "Gümüş";

  return "Çok Renkli";
}

function hasAll(text: string, tokens: string[]): boolean {
  return tokens.every((token) => text.includes(token));
}

/**
 * Converts confidence to a bounded number.
 *
 * @param {unknown} value Confidence value.
 * @return {number} Bounded confidence.
 */
function normalizeConfidence(value: unknown): number {
  if (typeof value !== "number" || Number.isNaN(value)) return 0.5;
  return Math.max(0, Math.min(1, value));
}

/**
 * Removes data URL prefix when present.
 *
 * @param {string} value Image base64.
 * @return {string} Bare base64.
 */
function stripDataUrlPrefix(value: string): string {
  return value.replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, "");
}

/**
 * Normalizes Turkish/English color text.
 *
 * @param {string} value Text.
 * @return {string} Normalized text.
 */
function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/ı/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c")
    .trim();
}

/**
 * Checks if a value is a JSON object.
 *
 * @param {unknown} value Unknown value.
 * @return {boolean} True for object.
 */
function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Checks if a value is a non-empty string.
 *
 * @param {unknown} value Unknown value.
 * @return {boolean} True when non-empty string.
 */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Error with HTTP status.
 */
class HttpError extends Error {
  readonly statusCode: number;

  /**
   * Creates HTTP error.
   *
   * @param {number} statusCode HTTP status.
   * @param {string} message Public message.
   */
  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
  }
}
