import axios, { isAxiosError } from "axios";
import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const GEMINI_MODEL_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/" +
  "gemini-2.5-flash-lite:generateContent";
const GEMINI_TIMEOUT_MS = 30000;

type JsonObject = Record<string, unknown>;

interface DayInput {
  day: string;
  event: string;
  requested: boolean;
}

interface WardrobeInput {
  id: string;
  category: string;
  name: string;
  color?: string;
  season?: string[];
  style?: string[];
  fabric?: string;
}

interface OutfitRequestBody {
  planType: string;
  userProfile: {
    gender: string;
  };
  stylePriority: string[];
  days: DayInput[];
  wardrobe: WardrobeInput[];
  weather: Record<string, JsonObject>;
  refreshType?: string;
  replaceItem?: string | null;
  replaceIntent?: string | null;
  currentOutfit?: JsonObject | null;
}

interface OutfitItem {
  id: string;
  name: string;
}

interface OutfitDay {
  day: string;
  status: string;
  message: string | null;
  title: string | null;
  style_type: string | null;
  outfit: {
    top: OutfitItem | null;
    outerwear: OutfitItem | null;
    bottom: OutfitItem | null;
    shoes: OutfitItem | null;
    bag: OutfitItem | null;
    accessory: OutfitItem | null;
  };
  style_note: string | null;
  why_this_works: string | null;
  vibe: string | null;
  can_favorite: boolean;
}

interface OutfitResponseBody {
  plan_type: string;
  days: OutfitDay[];
}

/**
 * Error type that carries an HTTP status code for request handlers.
 */
class HttpError extends Error {
  readonly statusCode: number;

  /**
   * Creates an HTTP-aware error.
   *
   * @param {number} statusCode Response status code.
   * @param {string} message Public error message.
   */
  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
  }
}

const systemPrompt = `Sen SmartStyle uygulamasının premium stil danışmanısın.
Profesyonel bir moda stilisti gibi düşün ve öner.

═══ TEMEL KURALLAR ═══
- Gardıropta olmayan hiçbir parçayı önerme. Sadece verilen id ve name
  değerlerini kullan.
- Hava durumuna uygun olmayan parçaları seçme.
- Günlük etkinlik, stil önceliği, sezon, kumaş ve renk uyumunu birlikte
  değerlendir.
- Kombinler giyilebilir, tutarlı ve premium görünmelidir.
- Sadece geçerli JSON döndür. Markdown, açıklama veya kod bloğu yazma.
- JSON anahtarlarını değiştirme.

═══ TEKRAR KURALLARI ═══
- Üst giyim/top: aynı parça haftada en fazla 2 kez kullanılabilir.
- Alt giyim/bottom: aynı parça haftada en fazla 3 kez kullanılabilir.
- Ayakkabı/shoes: aynı parça haftada en fazla 4 kez kullanılabilir.
- Üst üste 2 ardışık gün aynı top + bottom kombinasyonunu tekrarlama.
- Tekrar zorunluysa why_this_works alanında bunu açıkla.

═══ RENK UYUM KURALLARI ═══
Renk çakışmasından kaçın, şu hiyerarşiyi takip et:
1. Nötr + nötr: her zaman güvenli.
2. Nötr + tek renk: güvenli.
3. İki farklı canlı renk: dikkatli ol; tamamlayıcı renkler tercih et.
4. Üç veya daha fazla canlı renk: kullanma.
Kural ihlali gerekiyorsa style_note alanında açıkla.

═══ HAVA DURUMU ÖNCELİĞİ ═══
- 30°C üstü: çok hafif kumaş, kısa kol/askılı öncelikli, outerwear KESİNLİKLE null.
- 24-29°C: hafif kumaş, kısa kol öncelikli, outerwear null.
  Sadece akşam/rüzgar/klimalı ortam için çok hafif katman opsiyonel.
- 20°C ve üstü: outerwear KESİNLİKLE null olmalı. Ceket, mont, blazer,
  kaban, puffer veya herhangi bir dış giyim seçme.
- 18-19°C: tek kat rahat giyim yeterli; outerwear ZORUNLU DEĞİL, sadece
  kullanıcı özellikle isterse veya akşam etkinliği varsa opsiyonel.
- 12-17°C: katmanlama önerilir; outerwear dolu olmalı.
- 7-11°C: belirgin dış giyim gerekli; kapalı ayakkabı öncelikli.
- 6°C altı: kalın dış giyim zorunlu; mont/kaban/puffer ve kapalı
  ayakkabı tercih et.
UYARI: 20°C ve üstü sıcaklıklarda outerwear seçmek kesin hatadır.
Bu durumda outerwear alanını her zaman null bırak.

═══ STİL NOTU YAZIM KURALLARI ═══
- style_note: Kombinin teknik gerekçesi. Renk uyumu, kumaş dengesi veya
  katmanlama mantığını açıkla.
- why_this_works: Kullanıcıya hitap eden motive edici bir cümle.
  İlk veya ikinci şahıs kullan.
- vibe: Tek kavram veya kısa ifade. Örnek: "Quiet luxury",
  "Off-duty model", "Parisian casual", "Smart weekend".
- title: Kombinin karakterini özetleyen 2-4 kelime.

═══ KULLANICI PROFİLİ ═══
- userProfile.gender alanı "male" ise etek, elbise, crop, bluz, topuklu,
  stiletto, palazzo, tayt, body, tulum gibi kadın odaklı parçaları KESİNLİKLE seçme.
- userProfile.gender alanı "female" ise gardıropta varsa etek, elbise,
  body, tulum, bluz, topuklu gibi parçaları uygun etkinliklerde değerlendir.
- Profil verisi yoksa gardırop kategorilerine ve stil önceliklerine göre
  cinsiyet varsayımı yapmadan öner.

═══ KADIN PLAN ÖNCELİKLERİ (ZORUNLU) ═══
userProfile.gender "female" VE event; date, dinner, special, specialEvent,
özel etkinlik, akşam yemeği veya davet ise kombin formülünü yaklaşık şu
dağılımla seç:
- %55 elbise veya tulum.
- %30 etek + gömlek/bluz/saten üst.
- %10 etek + body/kazak/triko.
- %5 diğer şık alternatifler.
Elbise/tulum alternatifi yoksa etekli formüle, etek yoksa şık pantolonlu
formüle düş. Aynı elbiseyi tüm date günlerine basma; uygun alternatif varsa
en az kullanılan şık formülü seç.
Ayakkabı önceliği: topuklu/stiletto > çizme/bot > loafer/klasik ayakkabı >
temiz sneaker. Spor ayakkabı sadece başka uygun ayakkabı yoksa seçilsin.
Sıradan t-shirt, hoodie, sweatshirt bu etkinlikler için son çare.

Kadın spor/gym event için:
- Üst önceliği: tişört > crop > body > spor üst > sweatshirt.
- Hava 24°C ve üstüyse alt önceliği şort.
- Hava daha serin/soğuksa alt önceliği eşofman/jogger > pantolon.
- Ayakkabı önceliği spor ayakkabı/sneaker; topuklu/stiletto kullanma.

Kadın normal/günlük event için:
- Öncelik pantolonlu kombinlerde olsun: pantolon+gömlek, pantolon+body,
  pantolon+tişört, pantolon+basic üst.
- Şort sadece sıcak havada veya pantolon yoksa seçilsin.
- Ayakkabı önceliği sneaker/spor ayakkabı; sonra loafer/bot.

═══ ELBISE / TULUM TEK PARÇA KURALI ═══
- Elbise veya tulum seçildiğinde bu tek başına kombin oluşturur.
- top alanına elbise/tulumu koy.
- bottom alanını KESİNLİKLE null bırak. Alt giyim ekleme.
- Elbise/tulum üzerine outerwear KESİNLİKLE önerme; outerwear null olmalı.
- Ayakkabı zorunlu, çanta/aksesuar opsiyonel.

═══ KÜLOTLU ÇORAP KURALI ═══
- Külotlu çorap yalnızca kadın kullanıcılar için geçerlidir.
- Seçim koşulları (HEPSİ sağlanmalı):
  a) Kombin elbise, etek veya tulum içeriyor olmalı.
  b) Hava 18°C veya altı OLMALI (sıcak havada kesinlikle seçme).
  c) Etkinlik date, dinner veya special olmalı.
- Bu koşullar sağlanırsa accessory alanında opsiyonel tamamlayıcı olarak
  seçebilirsin. Zorunlu değil, sadece opsiyonel.
- Spor, günlük, ofis veya sıcak hava kombinlerinde KESİNLİKLE seçme.

═══ ERKEK ÖZEL ETKİNLİK ÖNCELİĞİ (ZORUNLU) ═══
userProfile.gender "male" VE event; date, dinner, special, specialEvent,
özel etkinlik, akşam yemeği veya davet ise AŞAĞIDAKİ SIRAYA GÖRE seç:

1. Üst: gömlek (öncelikli) > polo > blazer altına basic üst.
   Hoodie, sweatshirt, sıradan t-shirt bu etkinliklerde son çare.
2. Alt: kumaş pantolon > chino > klasik pantolon > slim jean.
   Şort ve eşofman altı bu etkinliklerde kesinlikle kullanma.
3. Ayakkabı: loafer > derby > oxford > klasik bot > temiz sneaker.
   Spor sneaker, terlik bu etkinliklerde kullanma.
4. Dış giyim: hava soğuksa blazer > ceket > kaban. Hoodie dış giyim sayılmaz.

═══ EKSİK DURUMLAR ═══
- Uygun kombin oluşturulamazsa status: "skipped", message alanında
  sebebi Türkçe yaz.
- Dış giyim, çanta ve aksesuar yoksa null döndür.
- Zorunlu kategori top/shoes eksikse skipped yap.
- Bottom eksikse sadece top alanında elbise veya tulum varsa styled dönebilirsin.

═══ ZORUNLU ÇIKTI ŞEMASI ═══
{
  "plan_type": "weekly",
  "days": [
    {
      "day": "Monday",
      "status": "styled",
      "message": null,
      "title": "Clean Casual Friday",
      "style_type": "Casual",
      "outfit": {
        "top": {"id": "top_1", "name": "Beyaz pamuk t-shirt"},
        "outerwear": null,
        "bottom": {"id": "bottom_1", "name": "Koyu mavi slim jean"},
        "shoes": {"id": "shoe_1", "name": "Beyaz deri sneaker"},
        "bag": null,
        "accessory": null
      },
      "style_note": "Beyaz-lacivert-beyaz üçlüsü klasik nötr yığılması; sneaker kombinini casual tarafa çeker.",
      "why_this_works": "Gardırobunun en kolay giyilen kombinlerinden — düşünmeden harika görünürsün.",
      "vibe": "Effortless minimal",
      "can_favorite": true
    }
  ]
}`;


export const generateOutfitSuggestions = onRequest(
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

      logger.info("Generating Gemini outfit suggestions.", {
        planType: body.planType,
        daysCount: body.days.length,
        wardrobeCount: body.wardrobe.length,
        refreshType: body.refreshType ?? "none",
      });

      let output: OutfitResponseBody;

      try {
        const prompt = buildOutfitPrompt(body);
        const rawText = await callGemini(prompt, geminiApiKey.value());

        logger.info("Gemini outfit raw response received.", {
          responsePreview: rawText.substring(0, 1000),
        });

        const parsed = parseAndRepairJson(rawText);
        output = applyLocalPriorityRules(validateGeminiOutput(parsed, body), body);
      } catch (error) {
        logger.warn("Gemini outfit generation failed; using local fallback.", {
          error,
        });
        output = buildLocalOutfitSuggestions(body);
      }

      response.status(200).json({
        success: true,
        data: output,
      });
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.statusCode : 500;
      const message = error instanceof Error ?
        error.message :
        "Unknown server error.";

      logger.error("Outfit generation failed.", { error });

      response.status(statusCode).json({
        success: false,
        error: message,
      });
    }
  },
);

/**
 * Validates the HTTPS request payload.
 *
 * @param {unknown} value Request body.
 * @return {OutfitRequestBody} Validated request body.
 */
function validateRequestBody(value: unknown): OutfitRequestBody {
  if (!isObject(value)) {
    throw new HttpError(400, "Request body must be a JSON object.");
  }

  const body = value as JsonObject;

  if (!isNonEmptyString(body.planType)) {
    throw new HttpError(400, "planType is required.");
  }
  if (!Array.isArray(body.stylePriority)) {
    throw new HttpError(400, "stylePriority must be an array.");
  }
  if (!Array.isArray(body.days) || body.days.length === 0) {
    throw new HttpError(400, "days must be a non-empty array.");
  }
  if (!Array.isArray(body.wardrobe) || body.wardrobe.length === 0) {
    throw new HttpError(400, "wardrobe must be a non-empty array.");
  }
  if (!isObject(body.weather)) {
    throw new HttpError(400, "weather is required.");
  }

  const days = body.days.map(validateDay);
  const wardrobe = body.wardrobe.map(validateWardrobeItem);
  const stylePriority = body.stylePriority.map((style) => {
    if (!isNonEmptyString(style)) {
      throw new HttpError(400, "stylePriority values must be strings.");
    }
    return style;
  });

  return {
    planType: body.planType,
    userProfile: validateUserProfile(body.userProfile),
    stylePriority,
    days,
    wardrobe,
    weather: body.weather as Record<string, JsonObject>,
    refreshType: isNonEmptyString(body.refreshType) ?
      body.refreshType :
      "none",
    replaceItem: isNonEmptyString(body.replaceItem) ? body.replaceItem : null,
    replaceIntent: isNonEmptyString(body.replaceIntent) ?
      body.replaceIntent :
      null,
    currentOutfit: isObject(body.currentOutfit) ? body.currentOutfit : null,
  };
}

/**
 * Validates a day object.
 *
 * @param {unknown} value Day payload.
 * @return {DayInput} Validated day.
 */
function validateDay(value: unknown): DayInput {
  if (!isObject(value)) {
    throw new HttpError(400, "Each day must be an object.");
  }

  if (!isNonEmptyString(value.day)) {
    throw new HttpError(400, "Each day requires a day value.");
  }
  if (!isNonEmptyString(value.event)) {
    throw new HttpError(400, "Each day requires an event value.");
  }

  return {
    day: value.day,
    event: value.event,
    requested: value.requested === true,
  };
}

/**
 * Normalizes optional profile data sent by the app.
 *
 * @param {unknown} value User profile payload.
 * @return {{gender: string}} Normalized profile.
 */
function validateUserProfile(value: unknown): { gender: string } {
  if (!isObject(value)) return { gender: "unspecified" };

  const gender = isNonEmptyString(value.gender) ?
    value.gender.trim().toLowerCase() :
    "";
  if (gender === "male" || gender === "female") return { gender };

  return { gender: "unspecified" };
}

/**
 * Validates a wardrobe item object.
 *
 * @param {unknown} value Wardrobe payload.
 * @return {WardrobeInput} Validated wardrobe item.
 */
function validateWardrobeItem(value: unknown): WardrobeInput {
  if (!isObject(value)) {
    throw new HttpError(400, "Each wardrobe item must be an object.");
  }

  if (!isNonEmptyString(value.id)) {
    throw new HttpError(400, "Each wardrobe item requires an id.");
  }
  if (!isNonEmptyString(value.category)) {
    throw new HttpError(400, "Each wardrobe item requires a category.");
  }
  if (!isNonEmptyString(value.name)) {
    throw new HttpError(400, "Each wardrobe item requires a name.");
  }

  return {
    id: value.id,
    category: value.category,
    name: value.name,
    color: isNonEmptyString(value.color) ? value.color : undefined,
    season: toStringArray(value.season),
    style: toStringArray(value.style),
    fabric: isNonEmptyString(value.fabric) ? value.fabric : undefined,
  };
}

/**
 * Builds the dynamic prompt from app data.
 *
 * @param {OutfitRequestBody} body Validated request body.
 * @return {string} Gemini prompt.
 */
function buildOutfitPrompt(body: OutfitRequestBody): string {
  const requestedDays = body.days.filter((day) => day.requested);
  const payload = {
    planType: body.planType,
    userProfile: body.userProfile,
    stylePriority: body.stylePriority,
    days: requestedDays.length > 0 ? requestedDays : body.days,
    wardrobe: body.wardrobe,
    weather: body.weather,
    refreshType: body.refreshType ?? "none",
    replaceItem: body.replaceItem ?? null,
    replaceIntent: body.replaceIntent ?? null,
    currentOutfit: body.currentOutfit ?? null,
  };
  const replaceItemInstruction =
    body.refreshType === "replace_item" && isReplaceableSlot(body.replaceItem) ?
      [
        "",
        "Parca degistirme modu aktif.",
        `Sadece "${body.replaceItem}"`,
        "alanini degistir.",
        body.replaceIntent ?
          `Degisim niyeti: "${body.replaceIntent}".` :
          "Degisim niyeti: app_decides.",
        replaceIntentInstruction(body.replaceIntent),
        "currentOutfit icindeki diger tum alanlari",
        "aynen koru.",
        "title, style_note, why_this_works ve vibe",
        "metinlerini yeni parcaya gore",
        "guncelleyebilirsin ama outfit icinde sadece hedef parca farkli olsun.",
      ].join("\n") :
      "";

  return [
    systemPrompt,
    "",
    "Aşağıdaki SmartStyle verilerine göre kombin üret:",
    `Kullanıcı cinsiyeti: ${body.userProfile.gender}`,
    JSON.stringify(payload, null, 2),
    replaceItemInstruction,
    "",
    "Cevabın STRICT JSON ONLY olmalı.",
  ].join("\n");
}

/**
 * Builds a focused instruction for item replacement intent.
 *
 * @param {string | null | undefined} intent Replacement intent.
 * @return {string} Prompt instruction.
 */
function replaceIntentInstruction(intent?: string | null): string {
  switch (intent) {
    case "lighter":
      return "Daha ince/hafif parca sec: tisort, gomlek, polo, sort, ince ceket gibi.";
    case "warmer":
      return "Daha sicak tutan parca sec: kazak, sweatshirt, hoodie, triko, mont, kaban, bot gibi.";
    case "smarter":
      return "Daha sik parca sec: gomlek, blazer, chino, klasik ayakkabi, loafer gibi.";
    case "comfortable":
      return "Daha rahat parca sec: tisort, sweatshirt, hoodie, jean, esofman, sneaker gibi.";
    case "weather":
      return "Hava durumuna daha uygun parca sec; yagmur/soguk varsa kapali ve koruyucu tercih et.";
    case "casual":
      return "Daha gunluk/casual parca sec; sneaker, denim, basic ustler iyi adaydir.";
    case "color":
      return "Ayni kategori ve islevde kal ama mumkunse mevcut parcadan farkli renk sec.";
    case "auto":
    default:
      return "En iyi uyumu uygulama karar versin; hava, stil ve renk dengesini birlikte degerlendir.";
  }
}

/**
 * Calls Google Gemini GenerateContent API.
 *
 * @param {string} prompt Final prompt.
 * @param {string} apiKey Gemini API key.
 * @return {Promise<string>} Model text output.
 */
async function callGemini(prompt: string, apiKey: string): Promise<string> {
  if (!apiKey) {
    throw new HttpError(500, "GEMINI_API_KEY secret is not configured.");
  }

  try {
    const response = await axios.post(
      `${GEMINI_MODEL_URL}?key=${encodeURIComponent(apiKey)}`,
      {
        contents: [
          {
            role: "user",
            parts: [{ text: prompt }],
          },
        ],
        generationConfig: {
          temperature: 0.55,
          topP: 0.9,
          maxOutputTokens: 4096,
          responseMimeType: "application/json",
        },
      },
      {
        timeout: GEMINI_TIMEOUT_MS,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

    const text = response.data?.candidates?.[0]?.content?.parts
      ?.map((part: JsonObject) => part.text)
      ?.filter((part: unknown) => typeof part === "string")
      ?.join("");

    if (!isNonEmptyString(text)) {
      throw new HttpError(502, "Gemini returned an empty response.");
    }

    return text;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (isAxiosError(error) && error.code === "ECONNABORTED") {
      throw new HttpError(504, "Gemini request timed out.");
    }

    const detail = isAxiosError(error) ?
      error.response?.data ?? error.message :
      error;

    logger.error("Gemini API request failed.", { detail });

    if (isAxiosError(error) && error.response?.status === 429) {
      throw new HttpError(
        429,
        "Gemini API kotası doldu veya bu model için ücretsiz kota yok. " +
        "Lütfen biraz sonra tekrar dene ya da Google AI billing/kota " +
        "ayarlarını kontrol et.",
      );
    }

    throw new HttpError(502, "Gemini API request failed.");
  }
}

/**
 * Parses JSON and attempts controlled repair for common model formatting.
 *
 * @param {string} text Gemini text output.
 * @return {unknown} Parsed JSON.
 */
function parseAndRepairJson(text: string): unknown {
  const candidates = [
    text,
    stripCodeFence(text),
    extractJsonObject(text),
  ].filter(isNonEmptyString);

  for (const candidate of candidates) {
    const repaired = repairJsonString(candidate);

    try {
      return JSON.parse(repaired);
    } catch (error) {
      logger.warn("Gemini JSON parse attempt failed.", {
        error,
        preview: repaired.substring(0, 500),
      });
    }
  }

  throw new HttpError(502, "Gemini response was not valid JSON.");
}

/**
 * Validates Gemini JSON against SmartStyle response schema.
 *
 * @param {unknown} value Parsed JSON.
 * @param {OutfitRequestBody} requestBody Original request.
 * @return {OutfitResponseBody} Validated output.
 */
function validateGeminiOutput(
  value: unknown,
  requestBody: OutfitRequestBody,
): OutfitResponseBody {
  if (!isObject(value)) {
    throw new HttpError(502, "Gemini JSON output must be an object.");
  }

  if (!isNonEmptyString(value.plan_type)) {
    throw new HttpError(502, "Gemini output is missing plan_type.");
  }
  if (!Array.isArray(value.days)) {
    throw new HttpError(502, "Gemini output is missing days.");
  }

  const wardrobeIds = new Set(requestBody.wardrobe.map((item) => item.id));
  const wardrobeById = new Map(
    requestBody.wardrobe.map((item) => [item.id, item]),
  );
  const genderBlockedIds = new Set(
    requestBody.wardrobe
      .filter((item) =>
        isGenderIncompatible(item, requestBody.userProfile.gender),
      )
      .map((item) => item.id),
  );
  const days = value.days.map((day) => {
    const validatedDay = validateOutputDay(
      day,
      wardrobeIds,
      genderBlockedIds,
      wardrobeById,
      requestBody.weather,
    );
    return preserveLockedOutfitPieces(validatedDay, requestBody);
  });

  return {
    plan_type: value.plan_type,
    days,
  };
}

/**
 * Applies deterministic business priorities after Gemini responds.
 *
 * @param {OutfitResponseBody} output Valid Gemini output.
 * @param {OutfitRequestBody} requestBody Original request body.
 * @return {OutfitResponseBody} Output with critical local priorities applied.
 */
function applyLocalPriorityRules(
  output: OutfitResponseBody,
  requestBody: OutfitRequestBody,
): OutfitResponseBody {
  if (requestBody.refreshType === "replace_item") return output;

  const dayInputs = new Map(requestBody.days.map((day) => [day.day, day]));
  const usedItemCounts = new Map<string, number>();
  const days = output.days.map((day) => {
    const input = dayInputs.get(day.day);
    if (!input || day.status !== "styled") return day;

    const adjustedDay = applyLocalPriorityToDay(
      day,
      input,
      requestBody,
      usedItemCounts,
    );
    trackOutfitUsage(adjustedDay, usedItemCounts);
    return adjustedDay;
  });

  return { ...output, days };
}

/**
 * Builds a complete local outfit response when Gemini is unavailable.
 *
 * @param {OutfitRequestBody} body Validated request body.
 * @return {OutfitResponseBody} Local outfit suggestions.
 */
function buildLocalOutfitSuggestions(
  body: OutfitRequestBody,
): OutfitResponseBody {
  const requestedDays = body.days.filter((day) => day.requested);
  const usedItemCounts = new Map<string, number>();
  const days = (requestedDays.length > 0 ? requestedDays : body.days)
    .map((day) => {
      const outfitDay = buildLocalOutfitDay(day, body, usedItemCounts);
      trackOutfitUsage(outfitDay, usedItemCounts);
      return outfitDay;
    });

  return {
    plan_type: body.planType,
    days,
  };
}

/**
 * Applies local priorities to one styled day.
 *
 * @param {OutfitDay} day Styled day.
 * @param {DayInput} input Original day input.
 * @param {OutfitRequestBody} body Original request body.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {OutfitDay} Locally adjusted day.
 */
function applyLocalPriorityToDay(
  day: OutfitDay,
  input: DayInput,
  body: OutfitRequestBody,
  usedItemCounts: Map<string, number>,
): OutfitDay {
  const localDay = buildLocalOutfitDay(input, body, usedItemCounts);
  if (localDay.status !== "styled") return day;

  if (isSpecialEvent(input.event) || isSportEvent(input.event)) {
    return mergePriorityOutfit(day, localDay);
  }

  if (isDailyEvent(input.event)) {
    return mergePriorityOutfit(day, localDay);
  }

  return day;
}

/**
 * Builds one local outfit day from wardrobe and weather.
 *
 * @param {DayInput} day Day input.
 * @param {OutfitRequestBody} body Original request body.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {OutfitDay} Local day output.
 */
function buildLocalOutfitDay(
  day: DayInput,
  body: OutfitRequestBody,
  usedItemCounts: Map<string, number>,
): OutfitDay {
  const wardrobe = body.wardrobe.filter(
    (item) => !isGenderIncompatible(item, body.userProfile.gender),
  );
  const temp = weatherTempForDay(body.weather, day.day);
  const specialMode = femaleSpecialMode(
    wardrobe,
    body.userProfile.gender,
    day,
    usedItemCounts,
  );
  const top = selectTop(
    wardrobe,
    body.userProfile.gender,
    day.event,
    usedItemCounts,
    specialMode,
  );
  const bottom = selectBottom(
    wardrobe,
    body.userProfile.gender,
    day.event,
    temp,
    usedItemCounts,
    specialMode,
  );
  const shoes = selectShoes(wardrobe, day.event, usedItemCounts);
  const bag = firstMatchingItem(wardrobe, isBag, usedItemCounts);
  const accessory = selectAccessory(
    wardrobe,
    body.userProfile.gender,
    day,
    temp,
    usedItemCounts,
  );

  if (!top || !shoes) {
    return skippedLocalDay(day, "Uygun üst giyim veya ayakkabı bulunamadı.");
  }

  const onePiece = isOnePieceWardrobeItem(top);
  if (!onePiece && !bottom) {
    return skippedLocalDay(day, "Uygun alt giyim bulunamadı.");
  }

  return {
    day: day.day,
    status: "styled",
    message: null,
    title: localTitle(day.event),
    style_type: localStyleType(day.event),
    outfit: {
      top: toOutfitItem(top),
      outerwear: selectOuterwear(wardrobe, top, temp, usedItemCounts),
      bottom: onePiece ? null : toOutfitItem(bottom),
      shoes: toOutfitItem(shoes),
      bag: toOutfitItem(bag),
      accessory: toOutfitItem(accessory),
    },
    style_note: localStyleNote(day.event, temp),
    why_this_works: localWhyThisWorks(day.event),
    vibe: localVibe(day.event),
    can_favorite: true,
  };
}

/**
 * Merges local priority outfit pieces into a Gemini day.
 *
 * @param {OutfitDay} day Gemini day.
 * @param {OutfitDay} localDay Local priority day.
 * @return {OutfitDay} Merged day.
 */
function mergePriorityOutfit(day: OutfitDay, localDay: OutfitDay): OutfitDay {
  return {
    ...day,
    title: localDay.title ?? day.title,
    style_type: localDay.style_type ?? day.style_type,
    outfit: localDay.outfit,
    style_note: localDay.style_note ?? day.style_note,
    why_this_works: localDay.why_this_works ?? day.why_this_works,
    vibe: localDay.vibe ?? day.vibe,
  };
}

type FemaleSpecialMode = "dress" | "skirt_shirt" | "skirt_body_knit" | "other";

/**
 * Chooses the female special-event outfit formula with weighted variety.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {string} gender User gender.
 * @param {DayInput} day Day input.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {FemaleSpecialMode | null} Selected formula.
 */
function femaleSpecialMode(
  wardrobe: WardrobeInput[],
  gender: string,
  day: DayInput,
  usedItemCounts: Map<string, number>,
): FemaleSpecialMode | null {
  if (gender !== "female" || !isSpecialEvent(day.event)) return null;

  const tops = wardrobe.filter(isTopLike);
  const bottoms = wardrobe.filter(isBottomLike);
  const hasFreshDress = tops.some(
    (item) => isOnePieceWardrobeItem(item) &&
      (usedItemCounts.get(item.id) ?? 0) === 0,
  );
  const hasAnyDress = tops.some(isOnePieceWardrobeItem);
  const hasSkirt = bottoms.some(isSkirtLike);
  const weighted = weightedFemaleSpecialMode(day.day, day.event);

  if (weighted === "dress" && (hasFreshDress || !hasSkirt)) {
    return hasAnyDress ? "dress" : "skirt_shirt";
  }
  if (weighted === "skirt_shirt" && hasSkirt) return "skirt_shirt";
  if (weighted === "skirt_body_knit" && hasSkirt) return "skirt_body_knit";
  if (weighted === "other") return "other";

  if (hasSkirt && !hasFreshDress) return "skirt_shirt";
  if (hasAnyDress) return "dress";
  return hasSkirt ? "skirt_shirt" : "other";
}

/**
 * Maps a day/event key into the requested 55/30/10/5 distribution.
 *
 * @param {string} day Day key.
 * @param {string} event Event text.
 * @return {FemaleSpecialMode} Weighted formula.
 */
function weightedFemaleSpecialMode(day: string, event: string): FemaleSpecialMode {
  const value = stableHash(`${day}|${event}`) % 100;
  if (value < 55) return "dress";
  if (value < 85) return "skirt_shirt";
  if (value < 95) return "skirt_body_knit";
  return "other";
}

/**
 * Produces a stable non-crypto hash for deterministic choices.
 *
 * @param {string} value Source value.
 * @return {number} Positive hash.
 */
function stableHash(value: string): number {
  let hash = 0;
  for (const char of normalizeText(value)) {
    hash = ((hash * 31) + char.charCodeAt(0)) >>> 0;
  }
  return hash;
}

/**
 * Selects a top according to event and gender priorities.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {string} gender User gender.
 * @param {string} event Day event.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {WardrobeInput | null} Selected top.
 */
function selectTop(
  wardrobe: WardrobeInput[],
  gender: string,
  event: string,
  usedItemCounts: Map<string, number>,
  specialMode: FemaleSpecialMode | null = null,
): WardrobeInput | null {
  const tops = wardrobe.filter(isTopLike);

  if (gender === "female" && isSpecialEvent(event)) {
    if (specialMode === "dress") {
      return firstMatchingItem(tops, isOnePieceWardrobeItem, usedItemCounts) ??
        firstMatchingItem(tops, isSmartFemaleTop, usedItemCounts);
    }
    if (specialMode === "skirt_shirt") {
      return firstMatchingItem(tops, isSmartFemaleShirtTop, usedItemCounts) ??
        firstMatchingItem(tops, isSmartFemaleTop, usedItemCounts);
    }
    if (specialMode === "skirt_body_knit") {
      return firstMatchingItem(tops, isBodyOrKnitLike, usedItemCounts) ??
        firstMatchingItem(tops, isSmartFemaleTop, usedItemCounts);
    }

    return firstMatchingItem(tops, isSmartFemaleTop, usedItemCounts) ??
      firstMatchingItem(tops, isOnePieceWardrobeItem, usedItemCounts);
  }

  if (gender === "male" && isSpecialEvent(event)) {
    return firstMatchingItem(tops, isShirtLike, usedItemCounts) ??
      firstMatchingItem(tops, isPoloLike, usedItemCounts) ??
      firstMatchingItem(tops, isTopLike, usedItemCounts);
  }

  if (isSportEvent(event)) {
    return firstMatchingItem(tops, isSportFemaleTop, usedItemCounts) ??
      firstMatchingItem(tops, isSportTop, usedItemCounts) ??
      firstMatchingItem(tops, isTShirtLike, usedItemCounts) ??
      firstMatchingItem(tops, isTopLike, usedItemCounts);
  }

  return firstMatchingItem(tops, isShirtLike, usedItemCounts) ??
    firstMatchingItem(tops, isBodyLike, usedItemCounts) ??
    firstMatchingItem(tops, isTShirtLike, usedItemCounts) ??
    firstMatchingItem(tops, isTopLike, usedItemCounts);
}

/**
 * Selects a bottom according to event and weather priorities.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {string} gender User gender.
 * @param {string} event Day event.
 * @param {number | null} temp Temperature in Celsius.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {WardrobeInput | null} Selected bottom.
 */
function selectBottom(
  wardrobe: WardrobeInput[],
  gender: string,
  event: string,
  temp: number | null,
  usedItemCounts: Map<string, number>,
  specialMode: FemaleSpecialMode | null = null,
): WardrobeInput | null {
  const bottoms = wardrobe.filter(isBottomLike);
  const hot = temp !== null && temp >= 24;

  if (gender === "female" && isSpecialEvent(event)) {
    if (specialMode === "dress") return null;
    if (specialMode === "skirt_shirt" ||
      specialMode === "skirt_body_knit") {
      return firstMatchingItem(bottoms, isSkirtLike, usedItemCounts) ??
        firstMatchingItem(bottoms, isSmartPantsLike, usedItemCounts);
    }

    return firstMatchingItem(bottoms, isSkirtLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isSmartPantsLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isPantsLike, usedItemCounts);
  }

  if (gender === "male" && isSpecialEvent(event)) {
    return firstMatchingItem(bottoms, isSmartPantsLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isChinoLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isPantsLike, usedItemCounts);
  }

  if (isSportEvent(event)) {
    if (hot) {
      return firstMatchingItem(bottoms, isShortsLike, usedItemCounts) ??
        firstMatchingItem(bottoms, isSweatpantsLike, usedItemCounts) ??
        firstMatchingItem(bottoms, isPantsLike, usedItemCounts);
    }

    return firstMatchingItem(bottoms, isSweatpantsLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isPantsLike, usedItemCounts) ??
      firstMatchingItem(bottoms, isShortsLike, usedItemCounts);
  }

  return firstMatchingItem(bottoms, isPantsLike, usedItemCounts) ??
    firstMatchingItem(bottoms, isSkirtLike, usedItemCounts) ??
    firstMatchingItem(bottoms, isShortsLike, usedItemCounts);
}

/**
 * Selects shoes according to event priority.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {string} event Day event.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {WardrobeInput | null} Selected shoes.
 */
function selectShoes(
  wardrobe: WardrobeInput[],
  event: string,
  usedItemCounts: Map<string, number>,
): WardrobeInput | null {
  const shoes = wardrobe.filter(isShoesLike);

  if (isSpecialEvent(event)) {
    return firstMatchingItem(shoes, isHeelsLike, usedItemCounts) ??
      firstMatchingItem(shoes, isBootLike, usedItemCounts) ??
      firstMatchingItem(shoes, isElegantShoesLike, usedItemCounts) ??
      firstMatchingItem(shoes, isBootLike, usedItemCounts) ??
      firstMatchingItem(shoes, isCleanSneakerLike, usedItemCounts) ??
      firstMatchingItem(shoes, isShoesLike, usedItemCounts);
  }

  if (isSportEvent(event)) {
    return firstMatchingItem(shoes, isSneakerLike, usedItemCounts) ??
      firstMatchingItem(shoes, isShoesLike, usedItemCounts);
  }

  return firstMatchingItem(shoes, isCleanSneakerLike, usedItemCounts) ??
    firstMatchingItem(shoes, isLoaferLike, usedItemCounts) ??
    firstMatchingItem(shoes, isShoesLike, usedItemCounts);
}

/**
 * Selects weather-safe outerwear.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {WardrobeInput} top Selected top.
 * @param {number | null} temp Temperature in Celsius.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {WardrobeInput | null} Selected outerwear.
 */
function selectOuterwear(
  wardrobe: WardrobeInput[],
  top: WardrobeInput,
  temp: number | null,
  usedItemCounts: Map<string, number>,
): WardrobeInput | null {
  if (temp !== null && temp >= 20) return null;
  if (isOnePieceWardrobeItem(top)) return null;
  if (temp === null || temp >= 18) return null;

  const outerwear = wardrobe.filter(isOuterwearLike);
  if (temp <= 6) {
    return firstMatchingItem(outerwear, isHeavyOuterwearLike, usedItemCounts) ??
      firstMatchingItem(outerwear, isOuterwearLike, usedItemCounts);
  }

  return firstMatchingItem(outerwear, isOuterwearLike, usedItemCounts);
}

/**
 * Selects accessory with tights rule support.
 *
 * @param {WardrobeInput[]} wardrobe Available wardrobe.
 * @param {string} gender User gender.
 * @param {DayInput} day Day input.
 * @param {number | null} temp Temperature in Celsius.
 * @param {Map<string, number>} usedItemCounts Weekly usage lookup.
 * @return {WardrobeInput | null} Selected accessory.
 */
function selectAccessory(
  wardrobe: WardrobeInput[],
  gender: string,
  day: DayInput,
  temp: number | null,
  usedItemCounts: Map<string, number>,
): WardrobeInput | null {
  const accessories = wardrobe.filter(isAccessoryLike);
  if (gender === "female" && isSpecialEvent(day.event) &&
    temp !== null && temp <= 18) {
    return firstMatchingItem(accessories, isTightsLike, usedItemCounts) ??
      firstMatchingItem(accessories, isAccessoryLike, usedItemCounts);
  }

  return firstMatchingItem(
    accessories,
    (item) => !isTightsLike(item),
    usedItemCounts,
  );
}

/**
 * Builds a skipped fallback day.
 *
 * @param {DayInput} day Day input.
 * @param {string} message Skip reason.
 * @return {OutfitDay} Skipped day.
 */
function skippedLocalDay(day: DayInput, message: string): OutfitDay {
  return {
    day: day.day,
    status: "skipped",
    message,
    title: null,
    style_type: null,
    outfit: {
      top: null,
      outerwear: null,
      bottom: null,
      shoes: null,
      bag: null,
      accessory: null,
    },
    style_note: null,
    why_this_works: null,
    vibe: null,
    can_favorite: false,
  };
}

/**
 * Finds the first item matching a predicate.
 *
 * @param {WardrobeInput[]} items Candidate items.
 * @param {Function} predicate Match predicate.
 * @param {Map<string, number>} [usedItemCounts] Optional usage lookup.
 * @return {WardrobeInput | null} First matching item.
 */
function firstMatchingItem(
  items: WardrobeInput[],
  predicate: (item: WardrobeInput) => boolean,
  usedItemCounts?: Map<string, number>,
): WardrobeInput | null {
  const matches = items.filter(predicate);
  if (usedItemCounts === undefined) return matches[0] ?? null;

  matches.sort((a, b) => {
    const usageDiff = (usedItemCounts.get(a.id) ?? 0) -
      (usedItemCounts.get(b.id) ?? 0);
    if (usageDiff !== 0) return usageDiff;
    return items.indexOf(a) - items.indexOf(b);
  });

  return matches[0] ?? null;
}

/**
 * Converts wardrobe item to output item.
 *
 * @param {WardrobeInput | null} item Wardrobe item.
 * @return {OutfitItem | null} Outfit item.
 */
function toOutfitItem(item: WardrobeInput | null): OutfitItem | null {
  if (item === null) return null;
  return { id: item.id, name: item.name };
}

/**
 * Checks special/date events.
 *
 * @param {string} event Event text.
 * @return {boolean} True for special events.
 */
function isSpecialEvent(event: string): boolean {
  return hasAnyText(event, [
    "date",
    "dinner",
    "special",
    "specialevent",
    "özel",
    "ozel",
    "akşam yemeği",
    "aksam yemegi",
    "davet",
    "gece",
  ]);
}

/**
 * Checks sport events.
 *
 * @param {string} event Event text.
 * @return {boolean} True for sport events.
 */
function isSportEvent(event: string): boolean {
  return hasAnyText(event, [
    "spor",
    "sport",
    "gym",
    "fitness",
    "workout",
    "koşu",
    "kosu",
    "antrenman",
  ]);
}

/**
 * Checks daily casual events.
 *
 * @param {string} event Event text.
 * @return {boolean} True for daily events.
 */
function isDailyEvent(event: string): boolean {
  return hasAnyText(event, [
    "daily",
    "casual",
    "günlük",
    "gunluk",
    "okul",
    "school",
    "work",
    "iş",
    "is",
  ]);
}

/**
 * Builds compact local title.
 *
 * @param {string} event Event text.
 * @return {string} Outfit title.
 */
function localTitle(event: string): string {
  if (isSpecialEvent(event)) return "Net Date Şıklığı";
  if (isSportEvent(event)) return "Rahat Spor Kombin";
  return "Gündelik Dengeli Kombin";
}

/**
 * Builds local style type.
 *
 * @param {string} event Event text.
 * @return {string} Style type.
 */
function localStyleType(event: string): string {
  if (isSpecialEvent(event)) return "Smart Casual";
  if (isSportEvent(event)) return "Sport";
  return "Casual";
}

/**
 * Builds local style note.
 *
 * @param {string} event Event text.
 * @param {number | null} temp Temperature in Celsius.
 * @return {string} Style note.
 */
function localStyleNote(event: string, temp: number | null): string {
  const weatherNote = temp === null ?
    "hava verisine göre dengeli parçalarla" :
    `${temp}°C hava için katman ve kumaş dengesini koruyarak`;

  if (isSpecialEvent(event)) {
    return `${weatherNote} daha özenli ve temiz çizgide bir kombin kuruldu.`;
  }
  if (isSportEvent(event)) {
    return `${weatherNote} hareket rahatlığı öne alınarak spor parça seçildi.`;
  }

  return `${weatherNote} pantolon öncelikli gündelik bir denge kuruldu.`;
}

/**
 * Builds local motivational note.
 *
 * @param {string} event Event text.
 * @return {string} Why this works text.
 */
function localWhyThisWorks(event: string): string {
  if (isSpecialEvent(event)) {
    return "Date havasında sade ama daha özenli görünürsün.";
  }
  if (isSportEvent(event)) {
    return "Rahat hareket ederken kombinin yine düzenli görünür.";
  }

  return "Gün içinde düşünmeden giyebileceğin temiz bir kombin olur.";
}

/**
 * Builds local vibe.
 *
 * @param {string} event Event text.
 * @return {string} Outfit vibe.
 */
function localVibe(event: string): string {
  if (isSpecialEvent(event)) return "Smart date";
  if (isSportEvent(event)) return "Sport casual";
  return "Everyday clean";
}

function isTopLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "top",
    "üst",
    "ust",
    "tshirt",
    "t-shirt",
    "tişört",
    "tisort",
    "gömlek",
    "gomlek",
    "shirt",
    "polo",
    "bluz",
    "body",
    "crop",
    "elbise",
    "dress",
    "tulum",
    "jumpsuit",
    "sweatshirt",
    "hoodie",
  ]);
}

function isBottomLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "bottom",
    "alt",
    "pantolon",
    "pants",
    "trouser",
    "chino",
    "jean",
    "denim",
    "şort",
    "sort",
    "short",
    "etek",
    "skirt",
    "eşofman",
    "esofman",
    "jogger",
  ]);
}

function isShoesLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "shoes",
    "shoe",
    "ayakkabı",
    "ayakkabi",
    "sneaker",
    "loafer",
    "bot",
    "boot",
    "derby",
    "oxford",
    "stiletto",
    "topuklu",
  ]);
}

function isOuterwearLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "outerwear",
    "dış giyim",
    "dis giyim",
    "ceket",
    "jacket",
    "mont",
    "kaban",
    "coat",
    "blazer",
    "puffer",
    "parka",
    "hırka",
    "hirka",
  ]);
}

function isBag(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["bag", "çanta", "canta"]);
}

function isAccessoryLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "accessory",
    "aksesuar",
    "kemer",
    "belt",
    "saat",
    "watch",
    "kolye",
    "küpe",
    "kupe",
    "çorap",
    "corap",
  ]);
}

function isOnePieceWardrobeItem(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["elbise", "dress", "tulum", "jumpsuit"]);
}

function isSmartFemaleTop(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "bluz",
    "blouse",
    "body",
    "crop",
    "saten",
    "satin",
    "gömlek",
    "gomlek",
    "shirt",
  ]);
}

function isSmartFemaleShirtTop(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "gömlek",
    "gomlek",
    "shirt",
    "bluz",
    "blouse",
    "saten",
    "satin",
    "ipek",
    "silk",
  ]);
}

function isShirtLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["gömlek", "gomlek", "shirt", "oxford"]);
}

function isPoloLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["polo"]);
}

function isSportTop(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "sweatshirt",
    "hoodie",
    "spor",
    "sport",
    "training",
    "athletic",
    "tişört",
    "tisort",
    "t-shirt",
  ]);
}

function isSportFemaleTop(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "tişört",
    "tisort",
    "tshirt",
    "t-shirt",
    "crop",
    "body",
    "spor üst",
    "spor ust",
    "training",
    "athletic",
  ]);
}

function isTShirtLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["tişört", "tisort", "tshirt", "t-shirt"]);
}

function isBodyLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["body"]);
}

function isBodyOrKnitLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "body",
    "kazak",
    "knit",
    "triko",
    "sweater",
  ]);
}

function isSkirtLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["etek", "skirt"]);
}

function isPantsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "pantolon",
    "pants",
    "trouser",
    "jean",
    "denim",
    "chino",
  ]);
}

function isSmartPantsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "kumaş",
    "kumas",
    "chino",
    "klasik",
    "classic",
    "trouser",
    "pantolon",
  ]);
}

function isChinoLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["chino"]);
}

function isShortsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["şort", "sort", "short"]);
}

function isSweatpantsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "eşofman",
    "esofman",
    "jogger",
    "sweatpant",
  ]);
}

function isElegantShoesLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "loafer",
    "derby",
    "oxford",
    "topuklu",
    "stiletto",
    "heel",
    "klasik",
    "classic",
  ]);
}

function isHeelsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "topuklu",
    "stiletto",
    "heel",
    "blok topuk",
    "block heel",
    "ince bant",
  ]);
}

function isBootLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["çizme", "cizme", "bot", "boot"]);
}

function isSneakerLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["sneaker", "spor ayakkabı", "spor ayakkabi"]);
}

function isCleanSneakerLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["temiz sneaker", "beyaz sneaker", "sneaker"]);
}

function isLoaferLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["loafer"]);
}

function isHeavyOuterwearLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, ["mont", "kaban", "coat", "puffer", "parka"]);
}

function isTightsLike(item: WardrobeInput): boolean {
  return hasAnyItemText(item, [
    "külotlu çorap",
    "kulotlu corap",
    "tights",
    "pantyhose",
  ]);
}

/**
 * Checks whether an item text contains any token.
 *
 * @param {WardrobeInput} item Wardrobe item.
 * @param {string[]} tokens Search tokens.
 * @return {boolean} True when any token exists.
 */
function hasAnyItemText(item: WardrobeInput, tokens: string[]): boolean {
  return hasAnyText(itemSearchText(item), tokens);
}

/**
 * Checks whether text contains any token.
 *
 * @param {string} text Source text.
 * @param {string[]} tokens Search tokens.
 * @return {boolean} True when any token exists.
 */
function hasAnyText(text: string, tokens: string[]): boolean {
  const normalized = normalizeText(text);
  return tokens.some((token) => normalized.includes(normalizeText(token)));
}

/**
 * Builds a searchable item text.
 *
 * @param {WardrobeInput} item Wardrobe item.
 * @return {string} Searchable text.
 */
function itemSearchText(item: WardrobeInput): string {
  return [
    item.name,
    item.category,
    item.color,
    item.season,
    item.style,
    item.fabric,
  ].map((value) => JSON.stringify(value ?? "")).join(" ");
}

/**
 * Normalizes text for broad Turkish/English matching.
 *
 * @param {string} text Source text.
 * @return {string} Normalized text.
 */
function normalizeText(text: string): string {
  return text
    .toLocaleLowerCase("tr-TR")
    .replace(/ı/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c");
}

/**
 * Keeps all non-target outfit slots fixed during piece replacement.
 *
 * @param {OutfitDay} day Validated AI response day.
 * @param {OutfitRequestBody} requestBody Original request body.
 * @return {OutfitDay} Day with locked slots preserved.
 */
function preserveLockedOutfitPieces(
  day: OutfitDay,
  requestBody: OutfitRequestBody,
): OutfitDay {
  if (requestBody.refreshType !== "replace_item") return day;
  if (!isReplaceableSlot(requestBody.replaceItem)) return day;
  if (!isObject(requestBody.currentOutfit)) return day;

  const lockedSlots: ReplaceableSlot[] = REPLACEABLE_SLOTS.filter(
    (slot) => slot !== requestBody.replaceItem,
  );
  const preservedOutfit = { ...day.outfit };

  for (const slot of lockedSlots) {
    preservedOutfit[slot] = currentOutfitItem(requestBody.currentOutfit, slot);
  }

  return {
    ...day,
    outfit: preservedOutfit,
  };
}

/**
 * Validates one output day.
 *
 * @param {unknown} value Output day.
 * @param {Set<string>} wardrobeIds Valid wardrobe item ids.
 * @param {Set<string>} genderBlockedIds Gender-incompatible wardrobe ids.
 * @param {Map<string, WardrobeInput>} wardrobeById Wardrobe lookup.
 * @param {Record<string, JsonObject>} weatherByDay Weather lookup.
 * @return {OutfitDay} Validated day.
 */
function validateOutputDay(
  value: unknown,
  wardrobeIds: Set<string>,
  genderBlockedIds: Set<string>,
  wardrobeById: Map<string, WardrobeInput>,
  weatherByDay: Record<string, JsonObject>,
): OutfitDay {
  if (!isObject(value)) {
    throw new HttpError(502, "Each Gemini day output must be an object.");
  }

  if (!isNonEmptyString(value.day)) {
    throw new HttpError(502, "Gemini day output is missing day.");
  }
  if (!isNonEmptyString(value.status)) {
    throw new HttpError(502, "Gemini day output is missing status.");
  }
  if (!isObject(value.outfit)) {
    throw new HttpError(502, "Gemini day output is missing outfit.");
  }

  const outfit = value.outfit;

  const top = validateOutputItem(
    outfit.top,
    wardrobeIds,
    genderBlockedIds,
    wardrobeById,
    "top",
  );
  const outerwear = sanitizeOuterwear(
    validateOutputItem(
      outfit.outerwear,
      wardrobeIds,
      genderBlockedIds,
      wardrobeById,
      "outerwear",
    ),
    top,
    value.day,
    wardrobeById,
    weatherByDay,
  );

  return {
    day: value.day,
    status: value.status,
    message: nullableString(value.message),
    title: nullableString(value.title),
    style_type: nullableString(value.style_type),
    outfit: {
      top,
      outerwear,
      bottom: validateOutputItem(
        outfit.bottom,
        wardrobeIds,
        genderBlockedIds,
        wardrobeById,
        "bottom",
      ),
      shoes: validateOutputItem(
        outfit.shoes,
        wardrobeIds,
        genderBlockedIds,
        wardrobeById,
        "shoes",
      ),
      bag: validateOutputItem(
        outfit.bag,
        wardrobeIds,
        genderBlockedIds,
        wardrobeById,
        "bag",
      ),
      accessory: validateOutputItem(
        outfit.accessory,
        wardrobeIds,
        genderBlockedIds,
        wardrobeById,
        "accessory",
      ),
    },
    style_note: nullableString(value.style_note),
    why_this_works: nullableString(value.why_this_works),
    vibe: nullableString(value.vibe),
    can_favorite: value.can_favorite === true,
  };
}

/**
 * Enforces hard outerwear rules even when the model ignores the prompt.
 *
 * @param {OutfitItem | null} outerwear Gemini outerwear output.
 * @param {OutfitItem | null} top Gemini top output.
 * @param {string} day Day key.
 * @param {Map<string, WardrobeInput>} wardrobeById Wardrobe lookup.
 * @param {Record<string, JsonObject>} weatherByDay Weather lookup.
 * @return {OutfitItem | null} Sanitized outerwear.
 */
function sanitizeOuterwear(
  outerwear: OutfitItem | null,
  top: OutfitItem | null,
  day: string,
  wardrobeById: Map<string, WardrobeInput>,
  weatherByDay: Record<string, JsonObject>,
): OutfitItem | null {
  if (outerwear === null) return null;

  const temp = weatherTempForDay(weatherByDay, day);
  if (temp !== null && temp >= 20) return null;
  if (isOnePieceOutfitItem(top, wardrobeById)) return null;

  return outerwear;
}

/**
 * Reads the temperature sent by the Flutter app for a day.
 *
 * @param {Record<string, JsonObject>} weatherByDay Weather lookup.
 * @param {string} day Day key.
 * @return {number | null} Temperature in Celsius.
 */
function weatherTempForDay(
  weatherByDay: Record<string, JsonObject>,
  day: string,
): number | null {
  const weather = weatherByDay[day];
  if (!isObject(weather)) return null;

  const value = weather.temp ?? weather.temperature ?? weather.sicaklik;
  return typeof value === "number" ? value : null;
}

/**
 * Checks whether the selected top is a one-piece dress/jumpsuit.
 *
 * @param {OutfitItem | null} item Outfit item.
 * @param {Map<string, WardrobeInput>} wardrobeById Wardrobe lookup.
 * @return {boolean} True for dress/jumpsuit style pieces.
 */
function isOnePieceOutfitItem(
  item: OutfitItem | null,
  wardrobeById: Map<string, WardrobeInput>,
): boolean {
  if (item === null) return false;

  const wardrobeItem = wardrobeById.get(item.id);
  const text = [
    item.name,
    wardrobeItem?.name,
    wardrobeItem?.category,
    wardrobeItem?.style,
    wardrobeItem?.fabric,
  ].map((value) => JSON.stringify(value ?? "")).join(" ").toLowerCase();

  return text.includes("elbise") ||
    text.includes("tulum") ||
    text.includes("dress") ||
    text.includes("jumpsuit");
}

/**
 * Validates one outfit item and prevents hallucinated ids.
 *
 * @param {unknown} value Outfit item.
 * @param {Set<string>} wardrobeIds Valid wardrobe item ids.
 * @param {Set<string>} genderBlockedIds Gender-incompatible wardrobe ids.
 * @param {Map<string, WardrobeInput>} wardrobeById Wardrobe lookup.
 * @param {string} slot Outfit slot name.
 * @return {OutfitItem | null} Validated item or null.
 */
function validateOutputItem(
  value: unknown,
  wardrobeIds: Set<string>,
  genderBlockedIds: Set<string>,
  wardrobeById: Map<string, WardrobeInput>,
  slot: string,
): OutfitItem | null {
  if (value === null || value === undefined) return null;

  if (!isObject(value)) {
    throw new HttpError(502, `Gemini ${slot} item must be an object or null.`);
  }
  if (!isNonEmptyString(value.id) || !isNonEmptyString(value.name)) {
    throw new HttpError(502, `Gemini ${slot} item requires id and name.`);
  }
  if (!wardrobeIds.has(value.id)) {
    throw new HttpError(
      502,
      `Gemini selected unknown wardrobe item id: ${value.id}.`,
    );
  }
  if (genderBlockedIds.has(value.id)) {
    throw new HttpError(
      502,
      `Gender incompatible outfit item selected: ${value.id}.`,
    );
  }
  const wardrobeItem = wardrobeById.get(value.id);
  if (wardrobeItem !== undefined &&
    !isWardrobeItemAllowedInSlot(wardrobeItem, slot)) {
    throw new HttpError(
      502,
      `Gemini selected ${value.id} for incompatible slot: ${slot}.`,
    );
  }

  return {
    id: value.id,
    name: value.name,
  };
}

const REPLACEABLE_SLOTS = [
  "top",
  "outerwear",
  "bottom",
  "shoes",
  "bag",
  "accessory",
] as const;

type ReplaceableSlot = typeof REPLACEABLE_SLOTS[number];

/**
 * Checks whether the requested replacement slot is supported.
 *
 * @param {unknown} value Unknown slot value.
 * @return {boolean} True when the slot is replaceable.
 */
function isReplaceableSlot(value: unknown): value is ReplaceableSlot {
  return isNonEmptyString(value) &&
    REPLACEABLE_SLOTS.includes(value as ReplaceableSlot);
}

/**
 * Reads one current outfit item from the locked outfit payload.
 *
 * @param {JsonObject} currentOutfit Current outfit snapshot.
 * @param {ReplaceableSlot} slot Outfit slot name.
 * @return {OutfitItem | null} Preserved outfit item.
 */
function currentOutfitItem(
  currentOutfit: JsonObject,
  slot: ReplaceableSlot,
): OutfitItem | null {
  const value = currentOutfit[slot];
  if (value === null || value === undefined) return null;
  if (!isObject(value)) return null;
  if (!isNonEmptyString(value.id) || !isNonEmptyString(value.name)) {
    return null;
  }

  return {
    id: value.id,
    name: value.name,
  };
}

function isGenderIncompatible(item: WardrobeInput, gender: string): boolean {
  if (gender !== "male") return false;

  const text = [
    item.name,
    item.category,
    item.style,
    item.fabric,
  ].map((value) => JSON.stringify(value ?? "")).join(" ").toLowerCase();

  return [
    "etek",
    "elbise",
    "body",
    "tulum",
    "tayt",
    "topuklu",
    "stiletto",
    "blok topuk",
    "ince bant",
    "bluz",
    "crop",
    "palazzo",
    "cigarette",
    "kruvaze bluz",
    "wrap top",
    "saten midi",
    "pleated midi",
    "strappy heel",
    "block heel",
  ].some((token) => text.includes(token));
}

/**
 * Ensures Gemini did not put an item into the wrong outfit slot.
 *
 * @param {WardrobeInput} item Wardrobe item.
 * @param {string} slot Outfit slot.
 * @return {boolean} True when the item can occupy the slot.
 */
function isWardrobeItemAllowedInSlot(
  item: WardrobeInput,
  slot: string,
): boolean {
  switch (slot) {
    case "top":
      return isTopLike(item);
    case "outerwear":
      return isOuterwearLike(item);
    case "bottom":
      return isBottomLike(item);
    case "shoes":
      return isShoesLike(item);
    case "bag":
      return isBag(item);
    case "accessory":
      return isAccessoryLike(item);
    default:
      return false;
  }
}

/**
 * Tracks selected items for weekly variety.
 *
 * @param {OutfitDay} day Outfit day.
 * @param {Map<string, number>} usedItemCounts Usage lookup.
 */
function trackOutfitUsage(
  day: OutfitDay,
  usedItemCounts: Map<string, number>,
): void {
  if (day.status !== "styled") return;

  for (const item of Object.values(day.outfit)) {
    if (item === null) continue;
    usedItemCounts.set(item.id, (usedItemCounts.get(item.id) ?? 0) + 1);
  }
}

/**
 * Removes markdown JSON code fences.
 *
 * @param {string} text Raw model text.
 * @return {string} Text without fences.
 */
function stripCodeFence(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?/i, "")
    .replace(/```$/i, "")
    .trim();
}

/**
 * Extracts the first top-level JSON object.
 *
 * @param {string} text Raw model text.
 * @return {string} JSON-like object text.
 */
function extractJsonObject(text: string): string {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");

  if (start === -1 || end === -1 || end <= start) {
    return "";
  }

  return text.substring(start, end + 1);
}

/**
 * Repairs common JSON issues without changing semantic content.
 *
 * @param {string} text JSON-like text.
 * @return {string} Repaired JSON-like text.
 */
function repairJsonString(text: string): string {
  return stripCodeFence(text)
    .replace(/,\s*([}\]])/g, "$1")
    .replace(/[“”]/g, "\"")
    .replace(/[‘’]/g, "'");
}

/**
 * Converts unknown array values into string arrays.
 *
 * @param {unknown} value Unknown value.
 * @return {string[] | undefined} String array.
 */
function toStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;

  const items = value.filter(isNonEmptyString);
  return items.length > 0 ? items : undefined;
}

/**
 * Returns null for missing values and a string for scalar values.
 *
 * @param {unknown} value Unknown value.
 * @return {string | null} Nullable string.
 */
function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

/**
 * Checks if a value is a plain JSON object.
 *
 * @param {unknown} value Unknown value.
 * @return {boolean} True for non-array object.
 */
function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Checks if a value is a non-empty string.
 *
 * @param {unknown} value Unknown value.
 * @return {boolean} True for non-empty strings.
 */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
