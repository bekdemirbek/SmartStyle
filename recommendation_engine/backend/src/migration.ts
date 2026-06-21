import { autoTagItem } from "./autoTagItem.js";
import { Category, WardrobeItem } from "./types.js";

type LegacyWardrobeItem = Partial<WardrobeItem> & {
  type?: string;
  title?: string;
  tur?: string;
  kategori?: string;
  renk?: string;
};

/**
 * Converts existing wardrobe rows into the stricter rule-engine shape.
 * This is intentionally pure so it can run in a backend script, migration job, or client sync.
 */
export function migrateWardrobeItems(
  items: LegacyWardrobeItem[],
): WardrobeItem[] {
  return items.map(migrateWardrobeItem);
}

export function migrateWardrobeItem(item: LegacyWardrobeItem): WardrobeItem {
  return autoTagItem({
    ...item,
    name: item.name ?? item.type ?? item.title ?? item.tur ?? "Kıyafet",
    category: item.category ?? mapLegacyCategory(item.kategori),
    color: item.color ?? item.renk ?? "Belirtilmedi",
  });
}

function mapLegacyCategory(value?: string): Category | undefined {
  const text = normalize(value ?? "");
  if (text.includes("ust")) return "top";
  if (text.includes("alt")) return "bottom";
  if (text.includes("ayakkabi")) return "shoes";
  if (text.includes("dis")) return "outerwear";
  if (text.includes("aksesuar") || text.includes("corap")) return "accessory";
  return undefined;
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
