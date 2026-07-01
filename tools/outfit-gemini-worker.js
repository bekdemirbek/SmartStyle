/**
 * Cloudflare Worker — SmartStyle outfit generation via Gemini.
 *
 * Replaces the (now unreachable) Firebase Cloud Function
 * `generateOutfitSuggestions`. It receives the same request body the app
 * already sends, builds the same prompt, calls Gemini, and returns
 * `{ success, data }` in the same shape — so only the endpoint URL in
 * `lib/services/outfit_ai_service.dart` needs to change.
 *
 * Setup (Cloudflare dashboard, free, no card):
 *   1. Workers & Pages → Create → Worker → Deploy.
 *   2. Edit code → paste this file → Deploy.
 *   3. Settings → Variables and Secrets → add Secret:
 *        GEMINI_API_KEY = <your Gemini key>   (from Google AI Studio)
 *   4. Copy the *.workers.dev URL into OutfitAiService.endpoint.
 */

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/" +
  "gemini-2.5-flash-lite:generateContent";

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

═══ HAVA DURUMU ÖNCELİĞİ ═══
- 30°C üstü: çok hafif kumaş, kısa kol/askılı öncelikli, outerwear KESİNLİKLE null.
- 24-29°C: hafif kumaş, kısa kol öncelikli, outerwear null.
- 20°C ve üstü: outerwear KESİNLİKLE null olmalı.
- 18-19°C: tek kat rahat giyim yeterli; outerwear opsiyonel.
- 12-17°C: katmanlama önerilir; outerwear dolu olmalı.
- 6°C altı: kalın dış giyim zorunlu; kapalı ayakkabı tercih et.
UYARI: 20°C ve üstünde outerwear seçmek hatadır; null bırak.

═══ RENK UYUM KURALLARI ═══
1. Nötr + nötr: her zaman güvenli.
2. Nötr + tek renk: güvenli.
3. İki farklı canlı renk: dikkatli ol; tamamlayıcı renkler tercih et.
4. Üç veya daha fazla canlı renk: kullanma.

═══ CİNSİYET ═══
- userProfile.gender "male" ise etek, elbise, crop, bluz, topuklu, tulum,
  tayt gibi kadın odaklı parçaları KESİNLİKLE seçme.
- "female" ise uygun etkinliklerde etek/elbise/bluz/topuklu değerlendir.

═══ ELBISE / TULUM TEK PARÇA KURALI ═══
- Elbise/tulum seçildiğinde top alanına konur, bottom KESİNLİKLE null,
  outerwear null. Ayakkabı zorunlu; çanta/aksesuar opsiyonel.

═══ EKSİK DURUMLAR ═══
- Uygun kombin oluşturulamazsa status: "skipped", message alanında sebebi
  Türkçe yaz. Dış giyim/çanta/aksesuar yoksa null döndür.

═══ ZORUNLU ÇIKTI ŞEMASI ═══
{
  "plan_type": "weekly",
  "days": [
    {
      "day": "Monday",
      "status": "styled",
      "message": null,
      "title": "Clean Casual",
      "style_type": "Casual",
      "outfit": {
        "top": {"id": "top_1", "name": "Beyaz t-shirt"},
        "outerwear": null,
        "bottom": {"id": "bottom_1", "name": "Koyu jean"},
        "shoes": {"id": "shoe_1", "name": "Beyaz sneaker"},
        "bag": null,
        "accessory": null
      },
      "style_note": "Kısa teknik gerekçe.",
      "why_this_works": "Kullanıcıya hitap eden motive edici cümle.",
      "vibe": "Effortless minimal",
      "can_favorite": true
    }
  ]
}`;

const ALLOWED_ORIGINS = [
  "http://localhost",
  "http://localhost:8080",
  "http://127.0.0.1",
];

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const allowOrigin = ALLOWED_ORIGINS.some((o) => origin.startsWith(o))
      ? origin
      : "*";
    const cors = {
      "access-control-allow-origin": allowOrigin,
      "access-control-allow-methods": "POST,OPTIONS",
      "access-control-allow-headers": "content-type",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return json({ success: false, error: "Only POST supported." }, 405, cors);
    }
    if (!env.GEMINI_API_KEY) {
      return json({ success: false, error: "GEMINI_API_KEY not set." }, 500, cors);
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json({ success: false, error: "Invalid JSON body." }, 400, cors);
    }

    const requestedDays = Array.isArray(body.days)
      ? body.days.filter((d) => d && d.requested)
      : [];
    const payload = {
      planType: body.planType,
      userProfile: body.userProfile ?? { gender: "unspecified" },
      stylePriority: body.stylePriority ?? [],
      days: requestedDays.length > 0 ? requestedDays : body.days,
      wardrobe: body.wardrobe ?? [],
      weather: body.weather ?? {},
      refreshType: body.refreshType ?? "none",
      replaceItem: body.replaceItem ?? null,
      replaceIntent: body.replaceIntent ?? null,
      currentOutfit: body.currentOutfit ?? null,
    };

    const prompt = [
      systemPrompt,
      "",
      "Aşağıdaki SmartStyle verilerine göre kombin üret:",
      `Kullanıcı cinsiyeti: ${payload.userProfile.gender ?? "unspecified"}`,
      JSON.stringify(payload, null, 2),
      "",
      "Cevabın STRICT JSON ONLY olmalı.",
    ].join("\n");

    try {
      const res = await fetch(
        `${GEMINI_URL}?key=${encodeURIComponent(env.GEMINI_API_KEY)}`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: 0.55,
              topP: 0.9,
              maxOutputTokens: 4096,
              responseMimeType: "application/json",
            },
          }),
        },
      );

      if (!res.ok) {
        const detail = await res.text();
        return json(
          { success: false, error: `Gemini ${res.status}: ${detail.slice(0, 200)}` },
          502,
          cors,
        );
      }

      const data = await res.json();
      const text = (data.candidates?.[0]?.content?.parts || [])
        .map((p) => p.text)
        .filter((t) => typeof t === "string")
        .join("");

      const parsed = parseJson(text);
      if (!parsed || !Array.isArray(parsed.days)) {
        return json({ success: false, error: "Gemini invalid JSON." }, 502, cors);
      }

      return json({ success: true, data: parsed }, 200, cors);
    } catch (err) {
      return json({ success: false, error: String(err) }, 502, cors);
    }
  },
};

function parseJson(text) {
  if (!text) return null;
  const candidates = [
    text,
    text.replace(/```json/gi, "").replace(/```/g, "").trim(),
    (text.match(/\{[\s\S]*\}/) || [])[0],
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      return JSON.parse(c);
    } catch (_) {
      /* try next */
    }
  }
  return null;
}

function json(obj, status, cors) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}
