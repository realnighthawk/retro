package main

import (
	"encoding/json"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"os"
)

func main() {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(engine.New(nil, nil).OpenAPI()); err != nil {
		panic(err)
	}
}
