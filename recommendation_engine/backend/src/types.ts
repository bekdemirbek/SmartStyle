export type Occasion =
  | "formal"
  | "daily"
  | "sport"
  | "work"
  | "special"
  | "travel";

export type Category =
  | "top"
  | "bottom"
  | "shoes"
  | "accessory"
  | "outerwear";

export type Season = "spring" | "summer" | "fall" | "winter" | "all";

export type StyleTag =
  | "minimal"
  | "classic"
  | "casual"
  | "streetwear"
  | "bohemian"
  | "sport"
  | "smart casual";

export type ColorFamily = "neutral" | "warm" | "cool" | "earth";

export type Urgency = "immediate" | "browsing";

export type WardrobeItem = {
  id: string;
  name: string;
  category: Category;
  formality: 1 | 2 | 3 | 4 | 5;
  occasion: Occasion[];
  season: Season[];
  style: string[];
  color: string;
  colorFamily: ColorFamily;
  brand?: string;
  price?: number;
};

export type WardrobeSummary = {
  itemCount: number;
  categoryCounts: Record<Category, number>;
  dominantStyles: string[];
  dominantOccasions: Occasion[];
  dominantColors: string[];
  priceRange?: {
    min: number;
    max: number;
    median: number;
  };
};

export type PurchaseIntent = {
  occasion: Occasion | null;
  category: Category | null;
  style_hint: string | null;
  urgency: Urgency;
  user_wardrobe_summary: WardrobeSummary;
  follow_up_question?: string;
};

export type Recommendation = {
  item_name: string;
  color: string;
  style_tags: string[];
  occasion_tags: Occasion[];
  unlocks_combinations: number;
  confidence_score: number;
  why_this: string;
  match_count: number;
  fallback?: boolean;
};

export type RecommendRequest = {
  text?: string;
  selectedOccasion?: Occasion;
  selectedCategory?: Category;
  wardrobe: WardrobeItem[];
  currentCombinations: number;
};

export type RecommendResponse = {
  intent: PurchaseIntent;
  recommendations: Recommendation[];
  fallback: boolean;
  notice?: string;
};
