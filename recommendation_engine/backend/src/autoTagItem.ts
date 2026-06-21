import {
  Category,
  ColorFamily,
  Occasion,
  Season,
  WardrobeItem,
} from "./types.js";

const DEFAULT_OCCASION: Occasion[] = ["daily"];
const DEFAULT_SEASON: Season[] = ["all"];
const DEFAULT_STYLE = ["casual"];

type TagDraft = Partial<WardrobeItem> & {
  id?: string;
  name?: string;
  category?: Category;
};

/**
 * Adds rule-based tags to legacy or partially-entered items.
 * Keyword matching is deterministic; ambiguous items fall back to conservative daily tags.
 */
export function autoTagItem(item: TagDraft): WardrobeItem {
  const name = item.name?.trim() || "Untitled item";
  const category = item.category ?? inferCategory(name);
  const text = normalize(`${name} ${category}`);
  const formality = item.formality ?? inferFormality(text, category);
  const occasion = unique([
    ...(item.occasion ?? []),
    ...inferOccasion(text, formality),
  ]);
  const season = unique([...(item.season ?? []), ...inferSeason(text)]);
  const style = unique([...(item.style ?? []), ...inferStyle(text, formality)]);
  const color = item.color?.trim() || inferColor(text);
  const colorFamily = item.colorFamily ?? inferColorFamily(color);

  return {
    id: item.id ?? stableId(name, category),
    name,
    category,
    formality,
    occasion: occasion.length > 0 ? occasion : DEFAULT_OCCASION,
    season: season.length > 0 ? season : DEFAULT_SEASON,
    style: style.length > 0 ? style : DEFAULT_STYLE,
    color,
    colorFamily,
    brand: item.brand,
    price: item.price,
  };
}

/**
 * Placeholder integration point for a Gemini fallback.
 * Keep keyword tagging as the first pass, then call this only when the UI/backend
 * decides an item needs human-like disambiguation.
 */
export async function autoTagItemWithGeminiFallback(
  item: TagDraft,
  classifyWithGemini?: (item: TagDraft) => Promise<Partial<WardrobeItem>>,
): Promise<WardrobeItem> {
  const local = autoTagItem(item);
  if (!isAmbiguous(item.name ?? "") || !classifyWithGemini) return local;

  const geminiTags = await classifyWithGemini(item);
  return autoTagItem({ ...local, ...geminiTags });
}

function inferCategory(name: string): Category {
  const text = normalize(name);
  if (hasAny(text, ["ayakkabi", "sneaker", "bot", "loafer", "oxford"])) {
    return "shoes";
  }
  if (hasAny(text, ["pantolon", "jean", "chino", "sort", "etek", "tayt"])) {
    return "bottom";
  }
  if (hasAny(text, ["ceket", "mont", "kaban", "blazer", "trenckot"])) {
    return "outerwear";
  }
  if (hasAny(text, ["kemer", "saat", "canta", "sapka", "aksesuar"])) {
    return "accessory";
  }
  return "top";
}

function inferFormality(
  text: string,
  category: Category,
): WardrobeItem["formality"] {
  if (hasAny(text, ["esofman", "atlet", "spor", "kosu", "training"])) return 1;
  if (hasAny(text, ["tisort", "t-shirt", "jean", "sneaker", "hoodie"])) return 2;
  if (hasAny(text, ["gomlek", "chino", "loafer", "polo", "triko"])) return 3;
  if (hasAny(text, ["klasik ayakkabi", "klasik"])) return 4;
  if (hasAny(text, ["blazer", "slim pantolon", "oxford", "derby"])) return 4;
  if (hasAny(text, ["takim", "smokin", "rugan", "klasik ayakkabi"])) return 5;
  return category === "shoes" ? 2 : 2;
}

function inferOccasion(text: string, formality: number): Occasion[] {
  if (hasAny(text, ["spor", "gym", "kosu", "training", "esofman"])) {
    return ["sport", "daily"];
  }
  if (hasAny(text, ["blazer", "oxford", "derby", "ofis", "work"])) {
    return ["work", "formal", "special"];
  }
  if (hasAny(text, ["takim", "smokin", "rugan"])) {
    return ["formal", "special"];
  }
  if (formality >= 4) return ["work", "formal", "special"];
  if (formality === 3) return ["daily", "work"];
  return ["daily"];
}

function inferSeason(text: string): Season[] {
  if (hasAny(text, ["kaban", "mont", "kazak", "triko", "bot"])) {
    return ["fall", "winter"];
  }
  if (hasAny(text, ["sort", "keten", "atlet", "sandalet"])) {
    return ["spring", "summer"];
  }
  return ["all"];
}

function inferStyle(text: string, formality: number): string[] {
  const styles = new Set<string>();
  if (hasAny(text, ["minimal", "basic", "duz", "sade"])) styles.add("minimal");
  if (hasAny(text, ["klasik", "oxford", "derby", "blazer"])) styles.add("classic");
  if (hasAny(text, ["street", "oversize", "cargo", "chunky"])) styles.add("streetwear");
  if (hasAny(text, ["bohem", "bohemian"])) styles.add("bohemian");
  if (formality <= 2) styles.add("casual");
  if (formality >= 3 && formality <= 4) styles.add("classic");
  return [...styles];
}

function inferColor(text: string): string {
  const colorWords = [
    "siyah",
    "beyaz",
    "gri",
    "bej",
    "krem",
    "kahverengi",
    "lacivert",
    "mavi",
    "yesil",
    "kirmizi",
    "bordo",
    "pembe",
    "mor",
    "sari",
    "turuncu",
  ];

  return colorWords.find((color) => text.includes(color)) ?? "Belirtilmedi";
}

function inferColorFamily(color: string): ColorFamily {
  const text = normalize(color);
  if (["siyah", "beyaz", "gri", "lacivert"].includes(text)) return "neutral";
  if (["kirmizi", "bordo", "pembe", "sari", "turuncu"].includes(text)) {
    return "warm";
  }
  if (["mavi", "yesil", "mor"].includes(text)) return "cool";
  if (["bej", "krem", "kahverengi", "haki"].includes(text)) return "earth";
  return "neutral";
}

function isAmbiguous(name: string): boolean {
  const text = normalize(name);
  return text.length < 4 || ["ust", "alt", "kiyafet", "parca"].includes(text);
}

function stableId(name: string, category: Category): string {
  return `${category}_${normalize(name).replace(/[^a-z0-9]+/g, "_")}`;
}

function unique<T extends string>(values: T[]): T[] {
  return [...new Set(values.filter(Boolean))];
}

function hasAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(normalize(needle)));
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
