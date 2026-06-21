import { WardrobeItem } from "./types.js";

const OUTFIT_CATEGORIES = ["top", "bottom", "shoes", "outerwear"] as const;
const SEASONS = ["spring", "summer", "fall", "winter"] as const;

type OutfitCategory = (typeof OUTFIT_CATEGORIES)[number];

/**
 * Runs the hard validity rules for one outfit candidate.
 * Accessories may be present, but the outfit still needs exactly one top and one bottom.
 */
export function isValidCombination(items: WardrobeItem[]): boolean {
  if (!categoryRulesPass(items)) return false;
  if (!formalityCompatible(items)) return false;
  if (!occasionCompatible(items)) return false;
  if (!seasonCompatible(items)) return false;
  return true;
}

/**
 * Scores a combination from 0 to 1 for ranking.
 * Invalid combinations score 0; style coherence is a soft signal only.
 */
export function getCombinationScore(items: WardrobeItem[]): number {
  if (!isValidCombination(items)) return 0;

  const formalityScore = scoreFormalitySpread(items);
  const occasionScore = scoreOccasionOverlap(items);
  const styleScore = scoreStyleCoherence(items);

  return round2(formalityScore * 0.35 + occasionScore * 0.3 + styleScore * 0.35);
}

/**
 * Generates real outfit combinations and counts only combinations that pass the validator.
 * This replaces simple tops * bottoms * shoes math.
 */
export function countValidCombinations(wardrobe: WardrobeItem[]): number {
  return generateOutfitCombinations(wardrobe).filter(isValidCombination).length;
}

/**
 * Calculates the number of new valid combinations a purchase would unlock.
 */
export function getNewItemImpact(
  newItem: WardrobeItem,
  wardrobe: WardrobeItem[],
): number {
  const before = countValidCombinations(wardrobe);
  const after = countValidCombinations([...wardrobe, newItem]);
  return Math.max(0, after - before);
}

/**
 * Backward-compatible alias for older recommendation-engine callers.
 */
export function countSmartCombinations(wardrobe: WardrobeItem[]): number {
  return countValidCombinations(wardrobe);
}

/**
 * Backward-compatible alias for older recommendation-engine callers.
 */
export function countUnlockedCombinations(
  wardrobe: WardrobeItem[],
  candidate: WardrobeItem,
): number {
  return getNewItemImpact(candidate, wardrobe);
}

function generateOutfitCombinations(wardrobe: WardrobeItem[]): WardrobeItem[][] {
  const tops = byCategory(wardrobe, "top");
  const bottoms = byCategory(wardrobe, "bottom");
  const shoes = byCategory(wardrobe, "shoes");
  const outerwear = byCategory(wardrobe, "outerwear");
  const accessories = byCategory(wardrobe, "accessory");
  const shoeOptions = [null, ...shoes];
  const outerwearOptions = [null, ...outerwear];
  const accessoryOptions = [null, ...accessories];
  const combinations: WardrobeItem[][] = [];

  for (const top of tops) {
    for (const bottom of bottoms) {
      for (const shoe of shoeOptions) {
        for (const outer of outerwearOptions) {
          for (const accessory of accessoryOptions) {
            combinations.push(
              [top, bottom, shoe, outer, accessory].filter(
                (item): item is WardrobeItem => item !== null,
              ),
            );
          }
        }
      }
    }
  }

  return combinations;
}

function byCategory(
  wardrobe: WardrobeItem[],
  category: WardrobeItem["category"],
): WardrobeItem[] {
  return wardrobe.filter((item) => item.category === category);
}

function categoryRulesPass(items: WardrobeItem[]): boolean {
  const counts = new Map<WardrobeItem["category"], number>();
  for (const item of items) {
    counts.set(item.category, (counts.get(item.category) ?? 0) + 1);
  }

  if ((counts.get("top") ?? 0) !== 1) return false;
  if ((counts.get("bottom") ?? 0) !== 1) return false;
  if ((counts.get("shoes") ?? 0) > 1) return false;
  if ((counts.get("outerwear") ?? 0) > 1) return false;
  return true;
}

function formalityCompatible(items: WardrobeItem[]): boolean {
  const scores = items.map((item) => item.formality);
  return Math.max(...scores) - Math.min(...scores) <= 1;
}

function occasionCompatible(items: WardrobeItem[]): boolean {
  return intersection(items.map((item) => item.occasion)).size > 0;
}

function seasonCompatible(items: WardrobeItem[]): boolean {
  const normalized = items.map((item) =>
    item.season.includes("all") ? [...SEASONS] : item.season,
  );

  return intersection(normalized).size > 0;
}

function scoreFormalitySpread(items: WardrobeItem[]): number {
  const scores = items.map((item) => item.formality);
  const spread = Math.max(...scores) - Math.min(...scores);
  if (spread === 0) return 1;
  if (spread === 1) return 0.75;
  return 0;
}

function scoreOccasionOverlap(items: WardrobeItem[]): number {
  const shared = intersection(items.map((item) => item.occasion)).size;
  if (shared >= 3) return 1;
  if (shared === 2) return 0.85;
  if (shared === 1) return 0.7;
  return 0;
}

function scoreStyleCoherence(items: WardrobeItem[]): number {
  const shared = intersection(items.map((item) => item.style));
  if (shared.size === 0) return 0.3;
  if (shared.size === 1) return 0.7;
  if (shared.size === 2) return 0.85;
  return 1;
}

function intersection(values: string[][]): Set<string> {
  if (values.length === 0) return new Set();

  const shared = new Set(values[0]);
  for (const list of values.slice(1)) {
    for (const value of [...shared]) {
      if (!list.includes(value)) shared.delete(value);
    }
  }

  return shared;
}

function round2(value: number): number {
  return Number(value.toFixed(2));
}
