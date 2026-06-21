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

interface PurchaseRequestBody {
  contextText: string;
  userProfile: {
    gender: string;
  };
  selectedOccasion: string | null;
  selectedCategory: string | null;
  currentCombinations: number;
  wardrobe: JsonObject[];
}

class HttpError extends Error {
  readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
  }
}

export const generatePurchaseSuggestions = onRequest(
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
      const prompt = buildPrompt(body);
      const rawText = await callGemini(prompt, geminiApiKey.value());
      const parsed = parseJson(rawText);
      const recommendations = validateRecommendations(parsed, body);

      response.status(200).json({
        success: true,
        data: {recommendations},
      });
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.statusCode : 500;
      const message = error instanceof Error ?
        error.message :
        "Unknown server error.";

      logger.error("Purchase suggestions failed.", {error});
      response.status(statusCode).json({
        success: false,
        error: message,
      });
    }
  },
);

function validateRequestBody(value: unknown): PurchaseRequestBody {
  if (!isObject(value)) {
    throw new HttpError(400, "Request body must be a JSON object.");
  }

  const body = value as JsonObject;
  if (!Array.isArray(body.wardrobe)) {
    throw new HttpError(400, "wardrobe must be an array.");
  }

  return {
    contextText: typeof body.contextText === "string" ? body.contextText : "",
    userProfile: validateUserProfile(body.userProfile),
    selectedOccasion: nullableString(body.selectedOccasion),
    selectedCategory: nullableString(body.selectedCategory),
    currentCombinations: numberValue(body.currentCombinations),
    wardrobe: body.wardrobe.filter(isObject),
  };
}

function validateUserProfile(value: unknown): {gender: string} {
  if (!isObject(value)) return {gender: "unspecified"};

  const gender = typeof value.gender === "string" ?
    value.gender.trim().toLowerCase() :
    "";
  if (gender === "male" || gender === "female") return {gender};

  return {gender: "unspecified"};
}

function buildPrompt(body: PurchaseRequestBody): string {
  const wardrobeSummary = summarizeWardrobe(body.wardrobe);
  const contextRule = buildContextRule(body.selectedOccasion, body.contextText);
  const genderRule = buildGenderRule(body.userProfile.gender);
  const categoryRule = body.selectedCategory ?
    `- selectedCategory "${body.selectedCategory}" olduğu için sadece ` +
      `bu kategoriden öner.` :
    "- Kategori serbestse dolapta en zayıf/eksik kalan kategoriyi " +
      "önceliklendir.";

  return `Sen profesyonel bir kapsül gardırop danışmanısın. SmartStyle ` +
    `kullanıcısının mevcut dolabını analiz ederek en fazla 3 adet eksik, ` +
    `şık ve satın alınabilir parça öneriyorsun.

KULLANICI BİLGİSİ:
- Cinsiyet: ${body.userProfile.gender}
- Kullanım bağlamı: ${contextRule.label}
- Kullanıcı metni: ${body.contextText || "Yok"}
- Seçilen kategori: ${body.selectedCategory ?? "Yok"}
- Mevcut kombin sayısı: ${body.currentCombinations}

MEVCUT DOLAP ANALİZİ:
${wardrobeSummary}

GÖREVİN:
1. Dolapta az temsil edilen kategorileri, renkleri, stilleri ve kullanım
   bağlamlarını analiz et.
2. Mevcut parçalarla gerçekten kombinlenebilecek eksik parçaları bul.
3. Kullanıcının seçtiği bağlama ve kategoriye uyan en fazla 3 öneri döndür.

ZORUNLU KURALLAR:
- Her zaman Türkçe cevap ver.
- Sadece geçerli JSON döndür. Markdown veya açıklama yazma.
- Kategori değil, spesifik ürün öner: "siyah ayakkabı" değil
  "siyah deri derby ayakkabı".
- En fazla 3 öneri ver.
- Aksesuar önerme: kemer, çanta, saat, takı, şapka, gözlük, atkı vb. yok.
- İzin verilen kategoriler sadece: upper | lower | shoes | outerwear.
${categoryRule}
- Dolaptaki mevcut parçanın aynısını veya çok benzerini önerme.
- Önerileri birbirinden farklı tut; aynı ürün tipinin küçük varyasyonlarını
  döndürme.
- confidence_score 0.70 altındaysa öneriyi listeye ekleme.

CİNSİYET KURALLARI:
${genderRule}

BAĞLAM KURALLARI:
${contextRule.rules}

Zorunlu JSON şeması:
{
  "recommendations": [
    {
      "item_name": "spesifik ürün adı",
      "category": "upper|lower|shoes|outerwear",
      "color": "renk",
      "style_tags": ["classic"],
      "occasion_tags": ["${contextRule.occasionTag}"],
      "formality": "casual|smart casual|semi-formal|formal",
      "unlocks_combinations": 12,
      "confidence_score": 0.86,
      "why_this": "1 cümle Türkçe açıklama; dolaptaki uyumu belirt",
      "match_count": 8
    }
  ]
}`;
}

function buildGenderRule(gender: string): string {
  if (gender === "male") {
    return `Kullanıcı erkek. Aşağıdaki parçaları kesinlikle önerme:
- etek, mini etek, midi etek, maxi etek, elbise, abiye, tulum
- bluz, crop, crop top, body, korset, dekolteli üst, kadın kesimi gömlek
- tayt, palazzo, cigarette pantolon, kadın kesimi bol paça pantolon
- topuklu ayakkabı, stiletto, platform topuk, kitten heel, ince topuklu bot
Yalnızca erkek modası veya net unisex parçalar öner.`;
  }

  if (gender === "female") {
    return `Kullanıcı kadın. Kadın modası ve unisex parçalar önerebilirsin; ` +
      `bağlama uymayan erkek kesimi parçaları önerme.`;
  }

  return "Cinsiyet belirsiz. Net unisex parçalar öner.";
}

function buildContextRule(
  selectedOccasion: string | null,
  contextText: string,
): {label: string; occasionTag: string; rules: string} {
  const context = normalizeText(`${selectedOccasion ?? ""} ${contextText}`);

  if (containsAny(context, ["spor", "sport", "gym", "fitness", "kosu"])) {
    return {
      label: "Spor / aktif kullanım",
      occasionTag: "sport",
      rules: `- Yalnızca spor ve aktif kullanıma uygun teknik parçalar öner.
- Örnekler: performans tişörtü, jogger pantolon, antrenman şortu,
  koşu/antrenman ayakkabısı, zip-up spor ceket.
- formality sadece "casual" olmalı.
- Jean, klasik gömlek, kumaş pantolon, blazer, elbise ve takım parçaları
  önerme.`,
    };
  }

  if (
    containsAny(context, [
      "wedding",
      "dugun",
      "nikah",
      "special",
      "ozel",
      "davet",
      "mezuniyet",
      "formal",
    ])
  ) {
    return {
      label: "Özel gün / etkinlik",
      occasionTag: "special",
      rules: `- Şık, semi-formal veya formal parçalar öner.
- Erkek için örnekler: slim fit blazer, oxford gömlek, kumaş pantolon,
  loafer veya derby ayakkabı, trençkot.
- Kadın için örnekler: midi elbise, blazer, saten bluz, kumaş pantolon,
  şık babet veya topuklu ayakkabı.
- formality "semi-formal" veya "formal" olmalı.
- Günlük tişört, spor giyim, yırtık jean önerme.`,
    };
  }

  if (
    containsAny(context, [
      "is icin",
      "is kiyafeti",
      "ofis",
      "office",
      "work",
      "toplanti",
    ])
  ) {
    return {
      label: "İş / ofis",
      occasionTag: "work",
      rules: `- İş ortamına uygun, profesyonel görünümlü parçalar öner.
- Örnekler: kumaş pantolon, klasik gömlek, blazer, oxford/derby ayakkabı,
  trençkot.
- formality "smart casual", "semi-formal" veya "formal" olmalı.
- Aşırı spor veya gece kıyafeti önerme.`,
    };
  }

  return {
    label: "Günlük kullanım",
    occasionTag: "daily",
    rules: `- Günlük ve rahat kullanıma uygun parçalar öner.
- Erkek alt giyim örnekleri: regular/slim fit chino, düz kesim jean,
  relaxed fit pantolon, keten pantolon.
- Üst giyim: basic tişört, polo, günlük gömlek, sweatshirt.
- Ayakkabı: sade sneaker, loafer, günlük bot.
- formality "casual" veya "smart casual" olmalı.
- Takım elbise, gece elbisesi, smokin ve teknik spor parçaları önerme.`,
  };
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
          responseMimeType: "application/json",
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
    return text;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (isAxiosError(error)) {
      const status = error.response?.status ?? 502;
      if (status === 429 || status === 403) {
        throw new HttpError(429, "Gemini kotası doldu.");
      }
    }
    throw new HttpError(502, "Gemini purchase request failed.");
  }
}

function parseJson(text: string): JsonObject {
  try {
    const parsed = JSON.parse(text);
    if (!isObject(parsed)) {
      throw new HttpError(502, "Gemini JSON output must be an object.");
    }
    return parsed;
  } catch {
    throw new HttpError(502, "Gemini response was not valid JSON.");
  }
}

function validateRecommendations(
  value: JsonObject,
  body: PurchaseRequestBody,
): JsonObject[] {
  const raw = value.recommendations;
  if (!Array.isArray(raw)) {
    throw new HttpError(502, "Gemini output is missing recommendations.");
  }

  const allowedCategories = new Set(["upper", "lower", "shoes", "outerwear"]);
  const seen = new Set<string>();
  const recommendations: JsonObject[] = [];

  for (const item of raw.filter(isObject)) {
    const category = stringValue(item.category);
    const itemName = stringValue(item.item_name);
    const color = stringValue(item.color);
    const confidence = clamp(numberValue(item.confidence_score), 0, 1);

    if (!itemName || !color) continue;
    if (!allowedCategories.has(category)) continue;
    if (body.selectedCategory && category !== body.selectedCategory) {
      continue;
    }
    if (confidence < 0.7) continue;
    if (isAccessory(item)) continue;
    if (isGenderIncompatible(item, body.userProfile.gender)) continue;
    if (hasSimilarWardrobeItem(item, body.wardrobe)) continue;

    const itemKey = normalizeText(`${category} ${color} ${itemName}`);
    if (seen.has(itemKey)) continue;
    seen.add(itemKey);

    recommendations.push({
      item_name: itemName,
      category,
      color,
      style_tags: stringArray(item.style_tags),
      occasion_tags: stringArray(item.occasion_tags),
      formality: stringValue(item.formality) || "smart casual",
      unlocks_combinations: Math.max(
        1,
        numberValue(item.unlocks_combinations),
      ),
      confidence_score: confidence,
      why_this: stringValue(item.why_this) ||
        "Dolabındaki parçalarla uyumlu bir tamamlayıcıdır.",
      match_count: Math.max(0, numberValue(item.match_count)),
    });
  }

  return recommendations.slice(0, 3);
}

function isGenderIncompatible(item: JsonObject, gender: string): boolean {
  if (gender !== "male") return false;

  const text = [
    item.item_name,
    item.category,
    item.style_tags,
    item.occasion_tags,
  ].map((value) => JSON.stringify(value ?? "")).join(" ").toLowerCase();

  return FEMALE_ONLY_KEYWORDS.some((token) => text.includes(token));
}

function isAccessory(item: JsonObject): boolean {
  const text = [
    item.item_name,
    item.category,
    item.style_tags,
    item.occasion_tags,
  ].map((value) => JSON.stringify(value ?? "")).join(" ").toLowerCase();

  return ACCESSORY_KEYWORDS.some((token) => text.includes(token));
}

function hasSimilarWardrobeItem(
  item: JsonObject,
  wardrobe: JsonObject[],
): boolean {
  const candidate = normalizeText([
    item.item_name,
    item.category,
    item.color,
  ].map((value) => String(value ?? "")).join(" "));
  const candidateTokens = tokenSet(candidate);

  if (candidateTokens.size === 0) return false;

  return wardrobe.some((wardrobeItem) => {
    const existing = normalizeText([
      wardrobeItem.type,
      wardrobeItem.name,
      wardrobeItem.item_name,
      wardrobeItem.category,
      wardrobeItem.color,
    ].map((value) => String(value ?? "")).join(" "));
    const existingTokens = tokenSet(existing);
    if (existingTokens.size === 0) return false;

    const overlap = [...candidateTokens].filter((token) =>
      existingTokens.has(token),
    ).length;
    const union = new Set([...candidateTokens, ...existingTokens]).size;
    return union > 0 && overlap / union >= 0.55;
  });
}

const FEMALE_ONLY_KEYWORDS = [
  "etek",
  "mini etek",
  "midi etek",
  "maxi etek",
  "elbise",
  "abiye",
  "body",
  "korset",
  "tulum",
  "tayt",
  "topuklu",
  "stiletto",
  "platform topuk",
  "kitten heel",
  "blok topuk",
  "ince bant",
  "bluz",
  "crop",
  "crop top",
  "palazzo",
  "cigarette",
  "kadın kesimi",
  "kruvaze bluz",
  "wrap top",
  "saten midi",
  "pleated midi",
  "strappy heel",
  "block heel",
];

const ACCESSORY_KEYWORDS = [
  "kemer",
  "çanta",
  "canta",
  "saat",
  "takı",
  "taki",
  "kolye",
  "bileklik",
  "küpe",
  "kupe",
  "yüzük",
  "yuzuk",
  "şapka",
  "sapka",
  "bere",
  "gözlük",
  "gozluk",
  "eşarp",
  "esarp",
  "atkı",
  "atki",
  "eldiven",
  "cüzdan",
  "cuzdan",
];

function summarizeWardrobe(wardrobe: JsonObject[]): string {
  if (wardrobe.length === 0) return "Dolap boş.";

  const categoryCounts: Record<string, number> = {};
  const colors: Record<string, number> = {};
  const styles: Record<string, number> = {};
  const seasons: Record<string, number> = {};

  for (const item of wardrobe) {
    increment(categoryCounts, stringValue(item.category));
    increment(colors, stringValue(item.color));
    for (const style of stringArray(item.styleTags)) increment(styles, style);
    for (const season of stringArray(item.season)) increment(seasons, season);
  }

  const expectedCategories = ["upper", "lower", "shoes", "outerwear"];
  const missingCategories = expectedCategories.filter((category) =>
    (categoryCounts[category] ?? 0) < 2,
  );
  const itemList = wardrobe
    .slice(0, 30)
    .map((item) => {
      const category = stringValue(item.category) || "?";
      const color = stringValue(item.color) || "?";
      const type = stringValue(item.type) || stringValue(item.name) || "?";
      const styleTags = stringArray(item.styleTags).join(",") || "?";
      const itemSeasons = stringArray(item.season).join(",") || "?";
      return `- ${category} | ${color} | ${type} | stil:${styleTags} | ` +
        `mevsim:${itemSeasons}`;
    })
    .join("\n");

  return `Toplam parça: ${wardrobe.length}
Kategoriler: ${formatCounts(categoryCounts)}
Az/eksik kategoriler: ${
  missingCategories.length ? missingCategories.join(", ") : "yok"
}
Baskın renkler: ${formatTopCounts(colors, 5)}
Baskın stiller: ${formatTopCounts(styles, 5)}
Mevsim dağılımı: ${formatTopCounts(seasons, 4)}

Parçalar:
${itemList}`;
}

function increment(target: Record<string, number>, key: string) {
  if (!key) return;
  target[key] = (target[key] ?? 0) + 1;
}

function formatCounts(target: Record<string, number>): string {
  const entries = Object.entries(target);
  if (entries.length === 0) return "bilinmiyor";
  return entries.map(([key, value]) => `${key}:${value}`).join(", ");
}

function formatTopCounts(target: Record<string, number>, limit: number): string {
  const entries = Object.entries(target)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit);
  if (entries.length === 0) return "bilinmiyor";
  return entries.map(([key, value]) => `${key}(${value})`).join(", ");
}

function containsAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(needle));
}

function tokenSet(value: string): Set<string> {
  const stopWords = new Set([
    "bir",
    "ve",
    "ile",
    "fit",
    "slim",
    "regular",
    "relaxed",
    "basic",
    "klasik",
  ]);

  return new Set(
    normalizeText(value)
      .split(/\s+/)
      .filter((token) => token.length > 2 && !stopWords.has(token)),
  );
}

function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/ı/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") return Number(value) || 0;
  return 0;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item).trim()).filter(Boolean);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
