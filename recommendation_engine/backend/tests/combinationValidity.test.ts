import assert from "node:assert/strict";
import test from "node:test";

import {
  countValidCombinations,
  getCombinationScore,
  getNewItemImpact,
  isValidCombination,
} from "../src/combinationValidity.js";
import { autoTagItem } from "../src/autoTagItem.js";
import { migrateWardrobeItem } from "../src/migration.js";
import { WardrobeItem } from "../src/types.js";

test("atlet + jeans + knee-high boots is invalid because formality is too far apart", () => {
  const items = [
    item("atlet", "Atlet", "top", 1, ["daily", "sport"], ["summer"], ["casual"]),
    item("jean", "Mavi jean", "bottom", 2, ["daily"], ["all"], ["casual"]),
    item("cizme", "Siyah diz üstü çizme", "shoes", 4, ["special"], ["fall", "winter"], ["classic"]),
  ];

  assert.equal(isValidCombination(items), false);
  assert.equal(getCombinationScore(items), 0);
});

test("white t-shirt + jean + sneaker is a valid real-life daily combination", () => {
  const items = [
    item("tee", "Beyaz tişört", "top", 2, ["daily"], ["spring", "summer"], ["casual", "minimal"]),
    item("jean", "Mavi jean", "bottom", 2, ["daily"], ["all"], ["casual"]),
    item("sneaker", "Beyaz sneaker", "shoes", 2, ["daily"], ["all"], ["casual", "minimal"]),
  ];

  assert.equal(isValidCombination(items), true);
  assert.equal(getCombinationScore(items) > 0.7, true);
});

test("two tops in the same combination is invalid", () => {
  const items = [
    item("tee", "Beyaz tişört", "top", 2),
    item("shirt", "Gömlek", "top", 3),
    item("jean", "Jean", "bottom", 2),
    item("sneaker", "Sneaker", "shoes", 2),
  ];

  assert.equal(isValidCombination(items), false);
});

test("season must overlap unless all bridges the seasons", () => {
  const summerOnly = [
    item("linen", "Keten gömlek", "top", 3, ["daily"], ["summer"]),
    item("short", "Şort", "bottom", 2, ["daily"], ["summer"]),
    item("boot", "Kışlık bot", "shoes", 3, ["daily"], ["winter"]),
  ];
  const allSeasonShoes = [
    item("linen", "Keten gömlek", "top", 2, ["daily"], ["summer"]),
    item("short", "Şort", "bottom", 2, ["daily"], ["summer"]),
    item("sneaker", "Sneaker", "shoes", 2, ["daily"], ["all"]),
  ];

  assert.equal(isValidCombination(summerOnly), false);
  assert.equal(isValidCombination(allSeasonShoes), true);
});

test("countValidCombinations counts only outfits that pass every hard rule", () => {
  const wardrobe = [
    item("tee", "Beyaz tişört", "top", 2, ["daily"], ["all"], ["casual"]),
    item("atlet", "Atlet", "top", 1, ["sport"], ["summer"], ["casual"]),
    item("jean", "Jean", "bottom", 2, ["daily"], ["all"], ["casual"]),
    item("sneaker", "Sneaker", "shoes", 2, ["daily"], ["all"], ["casual"]),
    item("oxford", "Oxford ayakkabı", "shoes", 5, ["formal"], ["all"], ["classic"]),
  ];

  assert.equal(countValidCombinations(wardrobe), 2);
});

test("getNewItemImpact returns newly unlocked valid outfits", () => {
  const wardrobe = [
    item("tee", "Beyaz tişört", "top", 2, ["daily"], ["all"], ["casual"]),
    item("jean", "Jean", "bottom", 2, ["daily"], ["all"], ["casual"]),
  ];
  const sneaker = item("sneaker", "Beyaz sneaker", "shoes", 2, ["daily"], ["all"], ["casual"]);

  assert.equal(getNewItemImpact(sneaker, wardrobe), 1);
});

test("autoTagItem and migration helper add default rule-engine fields", () => {
  const tagged = autoTagItem({ id: "1", name: "Beyaz tişört", category: "top" });
  const migrated = migrateWardrobeItem({
    id: "2",
    tur: "Siyah klasik ayakkabı",
    kategori: "Ayakkabı",
    renk: "Siyah",
  });

  assert.equal(tagged.category, "top");
  assert.equal(tagged.formality, 2);
  assert.equal(tagged.colorFamily, "neutral");
  assert.equal(migrated.category, "shoes");
  assert.equal(migrated.formality >= 4, true);
});

function item(
  id: string,
  name: string,
  category: WardrobeItem["category"],
  formality: WardrobeItem["formality"],
  occasion: WardrobeItem["occasion"] = ["daily"],
  season: WardrobeItem["season"] = ["all"],
  style: WardrobeItem["style"] = ["casual"],
): WardrobeItem {
  return {
    id,
    name,
    category,
    formality,
    occasion,
    season,
    style,
    color: "Beyaz",
    colorFamily: "neutral",
  };
}
