package engine_test

import (
	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"testing"
)

// P4.2: filters, sort orders, keyset paging and the coverage count are tested against real rows.
func TestIntegrationGarmentSearchAndPaging(t *testing.T) {
	s := integrationService(t, nil)
	scope := "P4 search " + uuid.NewString() + " "
	create := func(name string, fields map[string]any) engine.Garment {
		body := map[string]any{"idempotency_key": uuid.NewString(), "name": scope + name, "category": "top"}
		for k, v := range fields {
			body[k] = v
		}
		return execute[engine.GarmentResult](t, s, "garments_create", body).Garment
	}
	create("Tie", map[string]any{"colours": []string{"blue"}, "seasons": []string{"autumn"}, "brand": "Seaside", "favourite": true})
	create("Tie", map[string]any{"colours": []string{"blue"}, "care": map[string]any{"wash_method": "dry_clean", "source": "manual"}})
	create("Tie", map[string]any{"availability": "needs_wash"})
	create("Anorak", map[string]any{"colours": []string{"Red"}, "notes": "waxed cotton"})
	create("Blazer", map[string]any{"category": "outerwear"})
	create("Cardigan", map[string]any{"care": map[string]any{"wash_method": "machine", "max_temp_c": 30, "cycle": "normal", "source": "manual", "confirmed": true}})
	all := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "limit": 50})
	if all.TotalMatches != 6 || len(all.Items) != 6 || all.NextCursor != nil {
		t.Fatalf("coverage: %d of %d, cursor %v", len(all.Items), all.TotalMatches, all.NextCursor)
	}
	for _, c := range []struct {
		body map[string]any
		want int64
	}{
		{map[string]any{"colour": "blue"}, 2},
		{map[string]any{"favourite": true}, 1},
		{map[string]any{"brand": "seaside"}, 1},
		{map[string]any{"notes": "WAXED"}, 1},
		{map[string]any{"season": "autumn"}, 1},
		{map[string]any{"wash_method": "dry_clean"}, 1},
		{map[string]any{"care_confirmed": true}, 1},
		{map[string]any{"care_confirmed": false}, 5},
		{map[string]any{"category": "outerwear"}, 1},
		{map[string]any{"availability": "needs_wash"}, 1},
		{map[string]any{"colour": "blue", "season": "autumn", "favourite": true}, 1},
		{map[string]any{"colour": "blue", "category": "outerwear"}, 0},
	} {
		body := map[string]any{"search": scope, "limit": 50}
		for k, v := range c.body {
			body[k] = v
		}
		page := execute[engine.GarmentPage](t, s, "garments_list", body)
		if page.TotalMatches != c.want || int64(len(page.Items)) != c.want {
			t.Fatalf("%v: %d of %d, wanted %d", c.body, len(page.Items), page.TotalMatches, c.want)
		}
	}
	errorCode(t, s, "garments_list", map[string]any{"search": scope, "wash_method": "tumble"}, "invalid_input")
	errorCode(t, s, "garments_list", map[string]any{"search": scope, "sort": "colour"}, "invalid_input")
	seen := map[string]bool{}
	var cursor *string
	for page := 0; page < 6; page++ {
		body := map[string]any{"search": scope, "limit": 2, "sort": "name"}
		if cursor != nil {
			body["cursor"] = *cursor
		}
		value := execute[engine.GarmentPage](t, s, "garments_list", body)
		if value.TotalMatches != 6 {
			t.Fatalf("page %d coverage: %d", page, value.TotalMatches)
		}
		for _, item := range value.Items {
			if seen[item.ID] {
				t.Fatalf("paging repeated %s", item.ID)
			}
			seen[item.ID] = true
		}
		if value.NextCursor == nil {
			break
		}
		if page == 0 {
			// A cursor is bound to its exact filter and sort request.
			errorCode(t, s, "garments_list", map[string]any{"search": scope, "limit": 2, "sort": "recent", "cursor": *value.NextCursor}, "invalid_input")
			errorCode(t, s, "garments_list", map[string]any{"search": scope, "limit": 2, "sort": "name", "colour": "blue", "cursor": *value.NextCursor}, "invalid_input")
		}
		cursor = value.NextCursor
	}
	if len(seen) != 6 {
		t.Fatalf("paging skipped records: %d of 6", len(seen))
	}
	for _, sort := range []string{"id", "name", "recent", "added"} {
		first := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "limit": 1, "sort": sort})
		second := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "limit": 1, "sort": sort, "cursor": *first.NextCursor})
		if len(first.Items) != 1 || len(second.Items) != 1 || first.Items[0].ID == second.Items[0].ID {
			t.Fatalf("%s sort repeated a record", sort)
		}
	}
	named := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "sort": "name", "limit": 50})
	for i := 1; i < len(named.Items); i++ {
		if named.Items[i-1].Name > named.Items[i].Name {
			t.Fatalf("name sort is not ordered: %s before %s", named.Items[i-1].Name, named.Items[i].Name)
		}
	}
	added := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "sort": "added", "limit": 50})
	for i := 1; i < len(added.Items); i++ {
		if added.Items[i-1].CreatedAt.Before(added.Items[i].CreatedAt) {
			t.Fatal("added sort is not newest first")
		}
	}
	_ = execute[engine.GarmentResult](t, s, "garments_archive", edit(all.Items[0].ID, all.Items[0].Version))
	hidden := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope})
	shown := execute[engine.GarmentPage](t, s, "garments_list", map[string]any{"search": scope, "include_archived": true})
	if hidden.TotalMatches != 5 || shown.TotalMatches != 6 {
		t.Fatalf("archive coverage: %d hidden %d shown", hidden.TotalMatches, shown.TotalMatches)
	}
}
