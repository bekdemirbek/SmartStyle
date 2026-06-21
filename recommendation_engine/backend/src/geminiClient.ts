import { Recommendation, PurchaseIntent, WardrobeItem } from "./types.js";

const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

export async function getGeminiRecommendations(input: {
  apiKey: string;
  wardrobe: WardrobeItem[];
  intent: PurchaseIntent;
  currentCombinations: number;
}): Promise<Recommendation[]> {
  const response = await fetch(`${GEMINI_ENDPOINT}?key=${input.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: {
        parts: [
          {
            text:
              "You are a personal stylist AI. You have access to the user's wardrobe data. " +
              "Recommend specific items to purchase based on their wardrobe gaps and the occasion. " +
              "Always respond in Turkish. Always recommend specific items with attributes, never categories. " +
              "Response must be valid JSON only.",
          },
        ],
      },
      contents: [
        {
          role: "user",
          parts: [{ text: buildPrompt(input) }],
        },
      ],
      generationConfig: {
        temperature: 0.35,
        responseMimeType: "application/json",
      },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini request failed: ${response.status} ${body}`);
  }

  const payload = await response.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") throw new Error("Gemini response text missing");

  return validateGeminiRecommendations(JSON.parse(text));
}

function buildPrompt(input: {
  wardrobe: WardrobeItem[];
  intent: PurchaseIntent;
  currentCombinations: number;
}): string {
  return `
Kullanıcının dolabı: ${JSON.stringify(input.intent.user_wardrobe_summary)}
Dolap parçaları: ${JSON.stringify(input.wardrobe)}
Durum: ${input.intent.occasion}, Kategori: ${input.intent.category}, Stil notu: ${input.intent.style_hint}
Mevcut kombin sayısı: ${input.currentCombinations}

En fazla 3 öneri ver. JSON şeması:
[
  {
    "item_name": "Türkçe spesifik ürün adı",
    "color": "renk",
    "style_tags": ["style"],
    "occasion_tags": ["daily|work|formal|sport|special|travel"],
    "unlocks_combinations": 0,
    "confidence_score": 0.0,
    "why_this": "1 cümle Türkçe açıklama",
    "match_count": 0
  }
]
`;
}

function validateGeminiRecommendations(value: unknown): Recommendation[] {
  if (!Array.isArray(value)) throw new Error("Gemini JSON must be an array");

  return value.slice(0, 3).map((raw) => {
    if (!raw || typeof raw !== "object") throw new Error("Invalid recommendation");
    const item = raw as Record<string, unknown>;

    return {
      item_name: requiredString(item.item_name, "item_name"),
      color: requiredString(item.color, "color"),
      style_tags: stringArray(item.style_tags),
      occasion_tags: stringArray(item.occasion_tags) as Recommendation["occasion_tags"],
      unlocks_combinations: numberValue(item.unlocks_combinations),
      confidence_score: clamp01(numberValue(item.confidence_score)),
      why_this: requiredString(item.why_this, "why_this"),
      match_count: numberValue(item.match_count),
      fallback: false,
    };
  });
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Missing ${field}`);
  }
  return value.trim();
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item).trim()).filter(Boolean);
}

function numberValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") return Number(value) || 0;
  return 0;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}
