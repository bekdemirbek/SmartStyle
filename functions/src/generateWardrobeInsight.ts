import axios, {isAxiosError} from "axios";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const GEMINI_MODEL_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/" +
  "gemini-1.5-flash:generateContent";
const GEMINI_TIMEOUT_MS = 30000;

type JsonObject = Record<string, unknown>;

interface WardrobeInsightRequest {
  totalItems: number;
  categoryDistribution: JsonObject;
  dominantColors: string[];
  seasonCounts: JsonObject;
  categoryBalance: number;
  colorHarmony: number;
  seasonBalance: number;
  versatility: number;
  overallScore: number;
  topCount: number;
  bottomCount: number;
  shoeCount: number;
}

class HttpError extends Error {
  readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
  }
}

export const generateWardrobeInsight = onRequest(
  {
    secrets: [geminiApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
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
      const prompt = buildPrompt(body);
      const insight = await callGemini(prompt, geminiApiKey.value());

      response.status(200).json({
        success: true,
        data: {insight},
      });
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.statusCode : 500;
      const message = error instanceof Error ?
        error.message :
        "Unknown server error.";

      logger.error("Wardrobe insight failed.", {error});
      response.status(statusCode).json({
        success: false,
        error: message,
      });
    }
  },
);

function validateRequestBody(value: unknown): WardrobeInsightRequest {
  if (!isObject(value)) {
    throw new HttpError(400, "Request body must be a JSON object.");
  }

  const body = value as JsonObject;

  return {
    totalItems: numberValue(body.totalItems),
    categoryDistribution: objectValue(body.categoryDistribution),
    dominantColors: stringArray(body.dominantColors),
    seasonCounts: objectValue(body.seasonCounts),
    categoryBalance: numberValue(body.categoryBalance),
    colorHarmony: numberValue(body.colorHarmony),
    seasonBalance: numberValue(body.seasonBalance),
    versatility: numberValue(body.versatility),
    overallScore: numberValue(body.overallScore),
    topCount: numberValue(body.topCount),
    bottomCount: numberValue(body.bottomCount),
    shoeCount: numberValue(body.shoeCount),
  };
}

function buildPrompt(body: WardrobeInsightRequest): string {
  return `Sen bir moda danışmanısın. Kullanıcının dolap analizi şu şekilde:

Toplam kıyafet: ${body.totalItems}
Kategori dağılımı: ${JSON.stringify(body.categoryDistribution)}
Baskın renkler: ${body.dominantColors.join(", ")}
Mevsim dağılımı: ${JSON.stringify(body.seasonCounts)}
Kategori dengesi skoru: ${body.categoryBalance}/100
Renk uyumu skoru: ${body.colorHarmony}/100
Mevsim dengesi skoru: ${body.seasonBalance}/100
Çok yönlülük skoru: ${body.versatility}/100
Genel skor: ${body.overallScore}/100
Üst/alt/ayakkabı sayısı: ${body.topCount}/${body.bottomCount}/${body.shoeCount}

En düşük skoru olan metriği iyileştirmek için somut 1-2 kıyafet önerisi ver.
Ayrıca mevcut dolabıyla oluşturabileceği 1 kombin öner.
Yanıtın 3-5 cümle olsun, Türkçe yaz, samimi ve pratik bir dil kullan.
Markdown, liste işareti veya JSON yazma; sadece düz metin döndür.`;
}

async function callGemini(prompt: string, apiKey: string): Promise<string> {
  if (!apiKey) {
    throw new HttpError(500, "GEMINI_API_KEY secret is not configured.");
  }

  try {
    const response = await axios.post(
      `${GEMINI_MODEL_URL}?key=${encodeURIComponent(apiKey)}`,
      {
        contents: [{role: "user", parts: [{text: prompt}]}],
        generationConfig: {
          temperature: 0.55,
        },
      },
      {
        headers: {"Content-Type": "application/json"},
        timeout: GEMINI_TIMEOUT_MS,
      },
    );

    const text = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new HttpError(502, "Gemini returned an empty response.");
    }
    return text.trim();
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (isAxiosError(error)) {
      const status = error.response?.status ?? 502;
      if (status === 429 || status === 403) {
        throw new HttpError(429, "Gemini kotası doldu.");
      }
    }
    throw new HttpError(502, "Gemini wardrobe insight request failed.");
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function objectValue(value: unknown): JsonObject {
  return isObject(value) ? value : {};
}

function numberValue(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item).trim())
    .filter((item) => item.length > 0);
}
