import {
  Category,
  Occasion,
  PurchaseIntent,
  Recommendation,
  WardrobeItem,
} from "./types.js";
import { countUnlockedCombinations } from "./combinationValidity.js";

const CANDIDATES: WardrobeItem[] = [
  item("buy_white_oxford", "Beyaz slim-fit Oxford gömlek", "top", "Beyaz", 4, ["work", "formal", "special"], ["classic", "smart casual"]),
  item("buy_navy_blazer", "Lacivert slim-fit blazer", "outerwear", "Lacivert", 4, ["work", "formal", "special"], ["classic", "smart casual"]),
  item("buy_black_derby", "Siyah deri derby ayakkabı", "shoes", "Siyah", 5, ["formal", "special", "work"], ["classic"]),
  item("buy_white_sneaker", "Minimal beyaz deri sneaker", "shoes", "Beyaz", 2, ["daily", "travel", "work"], ["minimal", "casual"]),
  item("buy_beige_chino", "Bej slim-fit chino pantolon", "bottom", "Bej", 3, ["daily", "work", "travel"], ["smart casual", "minimal"]),
  item("buy_black_jean", "Siyah düz kesim jean", "bottom", "Siyah", 2, ["daily", "travel"], ["casual", "streetwear"]),
  item("buy_light_jacket", "Gri ince mevsimlik ceket", "outerwear", "Gri", 2, ["daily", "travel"], ["minimal", "casual"]),
];

export function fallbackRecommendPurchase(input: {
  wardrobe: WardrobeItem[];
  intent: PurchaseIntent;
}): Recommendation[] {
  const { wardrobe, intent } = input;
  const category = intent.category ?? bestConnectorCategory(wardrobe);
  const occasion = intent.occasion;

  return CANDIDATES
    .filter((candidate) => candidate.category === category)
    .map((candidate) => {
      const unlocks = countUnlockedCombinations(wardrobe, candidate);
      const matchCount = countMatches(wardrobe, candidate);
      const score =
        unlocks * 2 +
        matchCount * 3 +
        occasionOverlapScore(candidate, occasion) +
        colorCompatibilityScore(wardrobe, candidate) +
        formalityScore(wardrobe, candidate);

      return {
        recommendation: {
          item_name: candidate.name,
          color: candidate.color,
          style_tags: candidate.style,
          occasion_tags: candidate.occasion,
          unlocks_combinations: Math.max(0, unlocks),
          confidence_score: confidence(score, intent),
          why_this: `${matchCount} mevcut parçayla uyumlu; ${Math.max(0, unlocks)} yeni akıllı kombin potansiyeli açar.`,
          match_count: matchCount,
          fallback: true,
        },
        score,
      };
    })
    .filter(({ recommendation }) => recommendation.unlocks_combinations > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map(({ recommendation }) => recommendation);
}

function bestConnectorCategory(wardrobe: WardrobeItem[]): Category {
  const counts: Record<Category, number> = {
    top: 0,
    bottom: 0,
    shoes: 0,
    accessory: 0,
    outerwear: 0,
  };

  for (const item of wardrobe) counts[item.category] += 1;

  return (["top", "bottom", "shoes", "outerwear"] as Category[]).sort(
    (a, b) => counts[a] - counts[b],
  )[0];
}

function countMatches(wardrobe: WardrobeItem[], candidate: WardrobeItem): number {
  return wardrobe.filter((item) => {
    const formalityOk = Math.abs(item.formality - candidate.formality) <= 1;
    const occasionOk = item.occasion.some((tag) => candidate.occasion.includes(tag));
    return formalityOk && occasionOk;
  }).length;
}

function occasionOverlapScore(candidate: WardrobeItem, occasion: Occasion | null): number {
  if (!occasion) return 0;
  return candidate.occasion.includes(occasion) ? 18 : -6;
}

function colorCompatibilityScore(wardrobe: WardrobeItem[], candidate: WardrobeItem): number {
  const neutralColors = new Set(["siyah", "beyaz", "gri", "bej", "lacivert", "kahverengi"]);
  const normalizedColor = candidate.color.toLowerCase();
  const wardrobeHasNeutralBase = wardrobe.some((item) =>
    neutralColors.has(item.color.toLowerCase()),
  );

  if (neutralColors.has(normalizedColor)) return wardrobeHasNeutralBase ? 8 : 14;
  return 3;
}

function formalityScore(wardrobe: WardrobeItem[], candidate: WardrobeItem): number {
  if (wardrobe.length === 0) return 0;
  const avg =
    wardrobe.reduce((sum, item) => sum + item.formality, 0) / wardrobe.length;
  return Math.abs(avg - candidate.formality) <= 1 ? 10 : 2;
}

function confidence(score: number, intent: PurchaseIntent): number {
  let value = Math.min(0.92, score / 100);
  if (intent.occasion) value += 0.04;
  if (intent.category) value += 0.04;
  return Number(Math.min(0.96, value).toFixed(2));
}

function item(
  id: string,
  name: string,
  category: Category,
  color: string,
  formality: 1 | 2 | 3 | 4 | 5,
  occasion: Occasion[],
  style: string[],
): WardrobeItem {
  return {
    id,
    name,
    category,
    color,
    formality,
    occasion,
    style,
    brand: undefined,
    season: ["all"],
    colorFamily: colorFamilyFor(color),
  };
}

function colorFamilyFor(color: string): WardrobeItem["colorFamily"] {
  const normalized = color.toLowerCase();
  if (["siyah", "beyaz", "gri", "lacivert"].includes(normalized)) {
    return "neutral";
  }
  if (["bej", "kahverengi", "haki"].includes(normalized)) return "earth";
  if (["mavi", "yeşil", "mor"].includes(normalized)) return "cool";
  return "warm";
}
