package engine

import (
	"github.com/google/uuid"
	"reflect"
	"strings"
	"testing"
)

func rankedGarment(category, name string) Garment {
	return Garment{ID: uuid.NewString(), Version: 1, GarmentData: GarmentData{Name: name, Category: category, Availability: "ready"}}
}
func containsPiece(option Suggestion, id string) bool {
	for _, item := range option.Items {
		if item.GarmentID == id {
			return true
		}
	}
	return false
}

func TestRankingPreferencesAndDefaultOccasion(t *testing.T) {
	preferred, plain, avoided := rankedGarment("top", "Preferred tee"), rankedGarment("top", "Plain tee"), rankedGarment("top", "Avoided tee")
	preferred.Colours = []string{" Sage "}
	preferred.Formality = "casual"
	avoided.Colours = []string{"RED"}
	bottom, feet := rankedGarment("bottom", "Trousers"), rankedGarment("footwear", "Shoes")
	p := preferenceDefaults()
	p.PreferredColours = []string{"sage"}
	p.AvoidedColours = []string{"red"}
	p.PreferredStyles = []string{"casual"}
	p.DefaultOccasion = "casual"
	p.Variety = "low"
	in := SuggestInput{Day: "2026-10-09"}
	result, e := buildSuggestions([]Garment{plain, avoided, preferred, bottom, feet}, in, p, nil)
	if e != nil || len(result) != 2 || !containsPiece(result[0], preferred.ID) {
		t.Fatalf("preferences did not rank the eligible choices: %+v %v", result, e)
	}
	for _, option := range result {
		if containsPiece(option, avoided.ID) {
			t.Fatal("avoided colour was silently admitted")
		}
	}
	if !strings.Contains(strings.Join(result[0].Reasons, "\n"), "occasion/formality") {
		t.Fatal("default occasion was not explained")
	}
	in.RequiredIDs = []string{avoided.ID}
	if _, e = buildSuggestions([]Garment{avoided, bottom, feet}, in, p, nil); e == nil || PublicError(e).Code != "conflict" {
		t.Fatal("a conflicting lock was silently dropped")
	}
}

func TestRepeatBoundaryAndUnderusedToggle(t *testing.T) {
	repeated, eligible, feet := rankedGarment("one_piece", "Recent dress"), rankedGarment("one_piece", "Older dress"), rankedGarment("footwear", "Shoes")
	recent, boundary := "2026-10-03", "2026-10-02"
	repeated.LastWornOn = &recent
	eligible.LastWornOn = &boundary
	p := preferenceDefaults()
	in := SuggestInput{Day: "2026-10-09"}
	result, e := buildSuggestions([]Garment{repeated, eligible, feet}, in, p, nil)
	if e != nil || len(result) != 1 || !containsPiece(result[0], eligible.ID) || containsPiece(result[0], repeated.ID) {
		t.Fatalf("repeat interval boundary lost: %+v %v", result, e)
	}
	in.RequiredIDs = []string{repeated.ID}
	if _, e = buildSuggestions([]Garment{repeated, eligible, feet}, in, p, nil); e == nil {
		t.Fatal("recent required garment bypassed the repeat rule")
	}
	p.AvoidRepeatDays = 0
	if _, e = buildSuggestions([]Garment{repeated, eligible, feet}, in, p, nil); e != nil {
		t.Fatal("explicit zero repeat interval was ignored")
	}
	eligible.WearDays = 50
	with, _ := garmentRank(eligible, in, p, ratingTotal{})
	p.PreferUnderusedItems = false
	without, _ := garmentRank(eligible, in, p, ratingTotal{})
	if with != without {
		t.Fatal("a heavily used item should not receive an underused bonus")
	}
	eligible.WearDays = 0
	p.PreferUnderusedItems = true
	with, _ = garmentRank(eligible, in, p, ratingTotal{})
	p.PreferUnderusedItems = false
	without, _ = garmentRank(eligible, in, p, ratingTotal{})
	if with-without != 5 {
		t.Fatal("underused preference did not control its score")
	}
}

func TestExplicitRatingsAffectRankingAndResetRemovesTheirEffect(t *testing.T) {
	liked, disliked, neutral, feet := rankedGarment("one_piece", "Liked dress"), rankedGarment("one_piece", "Disliked dress"), rankedGarment("one_piece", "Unrated dress"), rankedGarment("footwear", "Shoes")
	five, one := 5, 1
	wears := []ratedOutfit{{IDs: []string{liked.ID, feet.ID}, FeedbackData: FeedbackData{Rating: &five}}, {IDs: []string{disliked.ID, feet.ID}, FeedbackData: FeedbackData{StyleRating: &one}}, {IDs: []string{neutral.ID, feet.ID}, FeedbackData: FeedbackData{Comment: "Viewed and skipped"}}}
	p := preferenceDefaults()
	p.AvoidRepeatDays = 0
	p.PreferUnderusedItems = false
	p.Variety = "low"
	result, e := buildSuggestions([]Garment{liked, disliked, neutral, feet}, SuggestInput{Day: "2026-10-09"}, p, wears)
	if e != nil || len(result) != 3 || !containsPiece(result[0], liked.ID) || !containsPiece(result[2], disliked.ID) {
		t.Fatalf("explicit ratings not reflected: %+v %v", result, e)
	}
	pieces, _ := feedbackTotals(wears)
	if pieces[neutral.ID].count != 0 {
		t.Fatal("an unrated comment became implicit feedback")
	}
	wears[0].Rating = nil
	wears[1].StyleRating = nil
	pieces, looks := feedbackTotals(wears)
	if len(pieces) != 0 || len(looks) != 0 {
		t.Fatal("reset ratings still influenced ranking")
	}
}

func TestStableDailyReplayLocksLayersAndDifferentAlternatives(t *testing.T) {
	garments := []Garment{rankedGarment("top", "A"), rankedGarment("top", "B"), rankedGarment("top", "C"), rankedGarment("bottom", "Trousers"), rankedGarment("outerwear", "Coat"), rankedGarment("footwear", "Shoes")}
	p := preferenceDefaults()
	p.LayeringPreference = "minimal"
	in := SuggestInput{Day: "2026-10-09", RequiredIDs: []string{garments[3].ID}}
	first, e := buildSuggestions(garments, in, p, nil)
	if e != nil {
		t.Fatal(e)
	}
	reversed := append([]Garment{}, garments...)
	for i, j := 0, len(reversed)-1; i < j; i, j = i+1, j-1 {
		reversed[i], reversed[j] = reversed[j], reversed[i]
	}
	replay, e := buildSuggestions(reversed, in, p, nil)
	if e != nil || !reflect.DeepEqual(first, replay) {
		t.Fatal("same-day replay changed with inventory order")
	}
	for _, option := range first {
		if containsPiece(option, garments[4].ID) || !containsPiece(option, garments[3].ID) {
			t.Fatal("minimal layering or required piece was ignored")
		}
	}
	in.RequiredIDs = append(in.RequiredIDs, garments[4].ID)
	locked, e := buildSuggestions(garments, in, p, nil)
	if e != nil || !containsPiece(locked[0], garments[4].ID) {
		t.Fatal("a locked coat was dropped by minimal layering")
	}
	in.ExcludedCombinations = []string{locked[0].Fingerprint}
	alternatives, e := buildSuggestions(garments, in, p, nil)
	if e != nil || len(alternatives) == 0 {
		t.Fatal("no remaining alternative")
	}
	for _, option := range alternatives {
		if option.Fingerprint == locked[0].Fingerprint {
			t.Fatal("blocked combination returned")
		}
	}
}

func TestCompleteLookRanksAheadOfHigherScoringPartialLook(t *testing.T) {
	dress, top, feet := rankedGarment("one_piece", "Dress"), rankedGarment("top", "Preferred top"), rankedGarment("footwear", "Shoes")
	top.Colours = []string{"sage"}
	p := preferenceDefaults()
	p.PreferredColours = []string{"sage"}
	for variant := 0; variant < 3; variant++ {
		result, e := buildSuggestions([]Garment{dress, top, feet}, SuggestInput{Day: "2026-10-09", Variant: variant}, p, nil)
		if e != nil || len(result) != 2 || !containsPiece(result[0], dress.ID) || len(result[0].MissingRoles) != 0 {
			t.Fatalf("partial look displaced complete coverage for variant %d: %+v %v", variant, result, e)
		}
	}
}

func TestSwapReplacesOnlyItsRequestedRoleAndNeverDropsIt(t *testing.T) {
	dress, replacement, top, bottom, feet := rankedGarment("one_piece", "Original dress"), rankedGarment("one_piece", "Other dress"), rankedGarment("top", "Top"), rankedGarment("bottom", "Bottom"), rankedGarment("footwear", "Shoes")
	p := preferenceDefaults()
	in := SuggestInput{Day: "2026-10-09", RequiredIDs: []string{feet.ID}, ExcludedIDs: []string{dress.ID}, SwapRole: "one_piece"}
	result, e := buildSuggestions([]Garment{dress, replacement, top, bottom, feet}, in, p, nil)
	if e != nil || len(result) != 1 || !containsPiece(result[0], replacement.ID) || !containsPiece(result[0], feet.ID) || containsPiece(result[0], top.ID) || containsPiece(result[0], bottom.ID) {
		t.Fatalf("swap changed the outfit shape or fixed pieces: %+v %v", result, e)
	}
	in.ExcludedIDs = append(in.ExcludedIDs, replacement.ID)
	result, e = buildSuggestions([]Garment{dress, replacement, top, bottom, feet}, in, p, nil)
	if e != nil || len(result) != 0 {
		t.Fatal("exhausted dress swap silently changed to another role")
	}
	coat, otherCoat := rankedGarment("outerwear", "Coat"), rankedGarment("outerwear", "Other coat")
	p.LayeringPreference = "minimal"
	in = SuggestInput{Day: "2026-10-09", RequiredIDs: []string{dress.ID, feet.ID}, ExcludedIDs: []string{coat.ID}, SwapRole: "outer"}
	result, e = buildSuggestions([]Garment{dress, feet, coat, otherCoat}, in, p, nil)
	if e != nil || len(result) != 1 || !containsPiece(result[0], otherCoat.ID) {
		t.Fatal("minimal layering dropped the requested coat replacement")
	}
}
