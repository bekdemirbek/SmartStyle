import React, { useMemo, useState } from "react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";

type Occasion = "daily" | "work" | "special" | "sport" | "travel" | "formal";
type Category = "top" | "bottom" | "shoes" | "outerwear" | "accessory";

type Recommendation = {
  item_name: string;
  color: string;
  style_tags: string[];
  occasion_tags: string[];
  unlocks_combinations: number;
  confidence_score: number;
  why_this: string;
  match_count: number;
  fallback?: boolean;
};

type Props = {
  wardrobe: unknown[];
  currentCombinations: number;
};

const OCCASIONS: Array<{ label: string; value: Occasion }> = [
  { label: "Günlük", value: "daily" },
  { label: "İş", value: "work" },
  { label: "Özel Gün", value: "special" },
  { label: "Spor", value: "sport" },
  { label: "Seyahat", value: "travel" },
];

const CATEGORIES: Array<{ label: string; value: Category }> = [
  { label: "Üst Giyim", value: "top" },
  { label: "Alt Giyim", value: "bottom" },
  { label: "Ayakkabı", value: "shoes" },
  { label: "Dış Giyim", value: "outerwear" },
  { label: "Aksesuar", value: "accessory" },
];

export function WhatShouldIBuyFlow({
  wardrobe,
  currentCombinations,
}: Props) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [text, setText] = useState("");
  const [occasion, setOccasion] = useState<Occasion | undefined>();
  const [category, setCategory] = useState<Category | undefined>();
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [notice, setNotice] = useState<string | undefined>();
  const [loading, setLoading] = useState(false);

  const canRequest = useMemo(() => Boolean(category), [category]);

  async function requestRecommendations(nextCategory = category) {
    if (!nextCategory) {
      setStep(2);
      return;
    }

    setLoading(true);
    setNotice(undefined);

    try {
      const response = await fetch("/api/recommend-purchase", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text,
          selectedOccasion: occasion,
          selectedCategory: nextCategory,
          wardrobe,
          currentCombinations,
        }),
      });

      const json = await response.json();
      if (json.notice) setNotice(json.notice);

      if (!json.recommendations?.length && json.intent?.follow_up_question) {
        setStep(2);
        return;
      }

      setRecommendations(json.recommendations ?? []);
      setStep(3);
    } finally {
      setLoading(false);
    }
  }

  if (step === 2) {
    return (
      <ScrollView contentContainerStyle={{ padding: 18, gap: 12 }}>
        <Text style={{ fontSize: 22, fontWeight: "800" }}>
          Hangi kategoride öneri istersin?
        </Text>
        {CATEGORIES.map((option) => (
          <Pressable
            key={option.value}
            onPress={() => {
              setCategory(option.value);
              requestRecommendations(option.value);
            }}
            style={{ padding: 16, borderRadius: 12, backgroundColor: "#F1EFE9" }}
          >
            <Text style={{ fontWeight: "700" }}>{option.label}</Text>
          </Pressable>
        ))}
      </ScrollView>
    );
  }

  if (step === 3) {
    return (
      <ScrollView contentContainerStyle={{ padding: 18, gap: 12 }}>
        {notice ? (
          <Text style={{ padding: 12, borderRadius: 10, backgroundColor: "#FFF4D8" }}>
            {notice}
          </Text>
        ) : null}

        {recommendations
          .sort((a, b) => b.unlocks_combinations - a.unlocks_combinations)
          .map((item) => (
            <RecommendationCard key={item.item_name} item={item} />
          ))}

        <Pressable onPress={() => setStep(1)} style={{ padding: 14 }}>
          <Text>Yeni arama yap</Text>
        </Pressable>
      </ScrollView>
    );
  }

  return (
    <ScrollView contentContainerStyle={{ padding: 18, gap: 14 }}>
      <Text style={{ fontSize: 24, fontWeight: "900" }}>Ne için alıyorsun?</Text>
      <TextInput
        value={text}
        onChangeText={setText}
        placeholder="Örn: Düğüne gidiyorum, ofis için, günlük rahat..."
        style={{
          minHeight: 52,
          borderRadius: 12,
          borderWidth: 1,
          borderColor: "#DDD6CA",
          paddingHorizontal: 14,
        }}
      />

      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
        {OCCASIONS.map((option) => (
          <Pressable
            key={option.value}
            onPress={() => setOccasion(option.value)}
            style={{
              paddingHorizontal: 12,
              paddingVertical: 8,
              borderRadius: 999,
              backgroundColor: occasion === option.value ? "#D7B56D" : "#F1EFE9",
            }}
          >
            <Text style={{ fontWeight: "700" }}>{option.label}</Text>
          </Pressable>
        ))}
      </View>

      <Pressable
        onPress={() => (canRequest ? requestRecommendations() : setStep(2))}
        disabled={loading}
        style={{
          padding: 15,
          borderRadius: 12,
          alignItems: "center",
          backgroundColor: "#D7B56D",
        }}
      >
        {loading ? <ActivityIndicator /> : <Text style={{ fontWeight: "900" }}>Öneriyi Daralt</Text>}
      </Pressable>
    </ScrollView>
  );
}

function RecommendationCard({ item }: { item: Recommendation }) {
  return (
    <View style={{ padding: 16, borderRadius: 14, backgroundColor: "#F7F4EE", gap: 8 }}>
      <Text style={{ fontSize: 18, fontWeight: "900" }}>{item.item_name}</Text>
      <Text>{item.color}</Text>
      <Text>{item.style_tags.join(" · ")}</Text>
      <Text>{item.occasion_tags.join(" · ")}</Text>
      <Text style={{ fontWeight: "800" }}>
        +{item.unlocks_combinations} kombin · Güven %{Math.round(item.confidence_score * 100)}
      </Text>
      <Text>{item.why_this}</Text>
      <View style={{ flexDirection: "row", gap: 8 }}>
        <Pressable style={{ padding: 10 }}>
          <Text>Beğendim</Text>
        </Pressable>
        <Pressable style={{ padding: 10 }}>
          <Text>Beğenmedim</Text>
        </Pressable>
      </View>
    </View>
  );
}
