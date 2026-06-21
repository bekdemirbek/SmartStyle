import {
  Category,
  Occasion,
  PurchaseIntent,
  Urgency,
  WardrobeItem,
  WardrobeSummary,
} from "./types.js";

const OCCASION_KEYWORDS: Array<{
  match: string[];
  occasion: Occasion;
  styleHint?: string;
}> = [
  { match: ["dugun", "düğün", "nikah", "mezuniyet"], occasion: "special", styleHint: "formal" },
  { match: ["is", "iş", "ofis", "toplanti", "toplantı"], occasion: "work", styleHint: "smart casual" },
  { match: ["gunluk", "günlük", "okul", "kahve"], occasion: "daily", styleHint: "casual" },
  { match: ["spor", "gym", "fitness", "kosu", "koşu"], occasion: "sport", styleHint: "sport" },
  { match: ["seyahat", "tatil", "ucak", "uçak"], occasion: "travel", styleHint: "comfortable" },
  { match: ["resmi", "formal", "davetiye"], occasion: "formal", styleHint: "formal" },
];

const CATEGORY_KEYWORDS: Array<{ match: string[]; category: Category }> = [
  { match: ["gomlek", "gömlek", "tisort", "tişört", "kazak", "ust", "üst"], category: "top" },
  { match: ["pantolon", "jean", "chino", "sort", "şort", "alt"], category: "bottom" },
  { match: ["ayakkabi", "ayakkabı", "sneaker", "bot", "loafer"], category: "shoes" },
  { match: ["ceket", "mont", "blazer", "kaban", "dis", "dış"], category: "outerwear" },
  { match: ["aksesuar", "kemer", "canta", "çanta", "saat"], category: "accessory" },
];

export function parsePurchaseIntent(input: {
  text?: string;
  selectedOccasion?: Occasion;
  selectedCategory?: Category;
  wardrobe: WardrobeItem[];
}): PurchaseIntent {
  const text = normalize(input.text ?? "");
  const wardrobeSummary = summarizeWardrobe(input.wardrobe);
  const textOccasion = inferOccasion(text);
  const textCategory = inferCategory(text);
  const urgency = inferUrgency(text);

  const intent: PurchaseIntent = {
    occasion: textOccasion?.occasion ?? input.selectedOccasion ?? null,
    category: textCategory ?? input.selectedCategory ?? null,
    style_hint: textOccasion?.styleHint ?? inferStyleHint(text),
    urgency,
    user_wardrobe_summary: wardrobeSummary,
  };

  if (!intent.category) {
    intent.follow_up_question = "Hangi kategoride öneri istersin?";
  }

  return intent;
}

export function summarizeWardrobe(wardrobe: WardrobeItem[]): WardrobeSummary {
  const categoryCounts = {
    top: 0,
    bottom: 0,
    shoes: 0,
    accessory: 0,
    outerwear: 0,
  };

  for (const item of wardrobe) {
    categoryCounts[item.category] += 1;
  }

  const prices = wardrobe
    .map((item) => item.price)
    .filter((price): price is number => typeof price === "number")
    .sort((a, b) => a - b);

  return {
    itemCount: wardrobe.length,
    categoryCounts,
    dominantStyles: topValues(wardrobe.flatMap((item) => item.style), 3),
    dominantOccasions: topValues(wardrobe.flatMap((item) => item.occasion), 3) as Occasion[],
    dominantColors: topValues(wardrobe.map((item) => item.color), 5),
    priceRange:
      prices.length > 0
        ? {
            min: prices[0],
            max: prices[prices.length - 1],
            median: prices[Math.floor(prices.length / 2)],
          }
        : undefined,
  };
}

function inferOccasion(text: string) {
  return OCCASION_KEYWORDS.find((entry) =>
    entry.match.some((keyword) => text.includes(normalize(keyword))),
  );
}

function inferCategory(text: string): Category | null {
  return (
    CATEGORY_KEYWORDS.find((entry) =>
      entry.match.some((keyword) => text.includes(normalize(keyword))),
    )?.category ?? null
  );
}

function inferUrgency(text: string): Urgency {
  if (["bugun", "bugün", "yarin", "yarın", "acil", "hemen"].some((word) => text.includes(normalize(word)))) {
    return "immediate";
  }
  return "browsing";
}

function inferStyleHint(text: string): string | null {
  const styleWords = ["minimal", "classic", "klasik", "streetwear", "casual", "sport", "formal"];
  return styleWords.find((word) => text.includes(normalize(word))) ?? null;
}

function topValues(values: string[], count: number): string[] {
  const map = new Map<string, number>();
  for (const value of values.map(normalize).filter(Boolean)) {
    map.set(value, (map.get(value) ?? 0) + 1);
  }
  return [...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, count)
    .map(([value]) => value);
}

function normalize(value: string): string {
  return value
    .toLowerCase()
    .replaceAll("ı", "i")
    .replaceAll("ğ", "g")
    .replaceAll("ü", "u")
    .replaceAll("ş", "s")
    .replaceAll("ö", "o")
    .replaceAll("ç", "c")
    .trim();
}
