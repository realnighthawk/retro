package engine

import (
	"encoding/json"
	"strings"
)

func (s *Service) OpenAPI() map[string]any {
	schemas := map[string]any{}
	paths := map[string]any{}
	for _, op := range s.Operations() {
		refs := map[string]any{}
		for suffix, schema := range map[string]any{"input": op.InputSchema, "output": op.OutputSchema} {
			data, _ := json.Marshal(schema)
			var root map[string]any
			_ = json.Unmarshal(data, &root)
			name := op.Name + "_" + suffix
			rewriteRefs(root, name)
			if defs, ok := root["$defs"].(map[string]any); ok {
				for key, value := range defs {
					schemas[name+"_"+key] = value
				}
			}
			delete(root, "$defs")
			schemas[name] = root
			refs[suffix] = map[string]any{"$ref": "#/components/schemas/" + name}
		}
		paths["/api/v1/operations/"+op.Name] = map[string]any{"post": map[string]any{
			"operationId": op.Name, "description": op.Description, "x-mcp-tool": op.Name, "x-read-only": !op.Write,
			"security":    []any{map[string]any{"routerBearer": []string{}}},
			"requestBody": map[string]any{"required": true, "content": map[string]any{"application/json": map[string]any{"schema": refs["input"]}}},
			"responses": map[string]any{
				"200": map[string]any{"description": "Operation result", "content": map[string]any{"application/json": map[string]any{"schema": refs["output"]}}},
				"400": errorResponse("Invalid input"), "401": errorResponse("Authentication required by router"),
				"404": errorResponse("Record not found"), "409": errorResponse("Stale version, conflicting identity, or record in use"),
				"413": errorResponse("Request body exceeds 1 MiB"), "500": errorResponse("Internal error"), "503": errorResponse("Temporarily unavailable; retry with the same request key"),
			},
		}}
	}
	paths["/api/v1/media/{id}/content"] = map[string]any{
		"parameters": []any{map[string]any{"name": "id", "in": "path", "required": true, "schema": map[string]string{"type": "string", "format": "uuid"}}},
		"put":        map[string]any{"operationId": "media_upload", "description": "Upload the exact reserved JPEG/PNG bytes, maximum 12 MiB. Identical retries are safe.", "security": []any{map[string]any{"routerBearer": []string{}}}, "requestBody": map[string]any{"required": true, "content": map[string]any{"application/octet-stream": map[string]any{"schema": map[string]string{"type": "string", "format": "binary"}}, "image/jpeg": map[string]any{"schema": map[string]string{"type": "string", "format": "binary"}}, "image/png": map[string]any{"schema": map[string]string{"type": "string", "format": "binary"}}}}, "responses": map[string]any{"200": map[string]any{"description": "Photo status", "content": map[string]any{"application/json": map[string]any{"schema": map[string]string{"$ref": "#/components/schemas/media_get_output"}}}}, "400": errorResponse("Invalid bytes, size or checksum"), "401": errorResponse("Authentication required by router"), "404": errorResponse("Photo not found"), "413": errorResponse("Photo exceeds 12 MiB"), "503": errorResponse("Photo storage unavailable")}},
		"get":        map[string]any{"operationId": "media_content", "description": "Read a ready JPEG derivative; original sources are never served.", "security": []any{map[string]any{"routerBearer": []string{}}}, "parameters": []any{map[string]any{"name": "variant", "in": "query", "required": true, "schema": map[string]any{"type": "string", "enum": []string{"display", "thumbnail"}}}}, "responses": map[string]any{"200": map[string]any{"description": "Safe photo derivative", "content": map[string]any{"image/jpeg": map[string]any{"schema": map[string]string{"type": "string", "format": "binary"}}}}, "400": errorResponse("Invalid variant"), "401": errorResponse("Authentication required by router"), "404": errorResponse("Photo not found"), "409": errorResponse("Photo not ready"), "503": errorResponse("Photo storage unavailable")}},
	}
	schemas["Error"] = map[string]any{"type": "object", "required": []string{"error"}, "properties": map[string]any{
		"error": map[string]any{"type": "object", "required": []string{"code", "message"}, "properties": map[string]any{"code": map[string]string{"type": "string"}, "message": map[string]string{"type": "string"}}},
	}}
	return map[string]any{"openapi": "3.1.0", "info": map[string]string{"title": "Retro Wardrobe Engine", "version": "0.1.0", "description": "Wardrobe inventory, dated outfits and private photographs. One registry serves HTTP and MCP."},
		"servers": []any{map[string]string{"url": "/retro", "description": "Trusted identity router; direct engine uses /"}},
		"paths":   paths, "components": map[string]any{"schemas": schemas, "securitySchemes": map[string]any{"routerBearer": map[string]string{
			"type": "http", "scheme": "bearer", "bearerFormat": "JWT", "description": "Verified by the identity router; the private engine has no authentication or user identity handling.",
		}}}}
}
func errorResponse(description string) map[string]any {
	return map[string]any{"description": description, "content": map[string]any{"application/json": map[string]any{"schema": map[string]string{"$ref": "#/components/schemas/Error"}}}}
}
func rewriteRefs(value any, prefix string) {
	switch v := value.(type) {
	case map[string]any:
		for key, item := range v {
			if key == "$ref" {
				if ref, ok := item.(string); ok && strings.HasPrefix(ref, "#/$defs/") {
					v[key] = "#/components/schemas/" + prefix + "_" + strings.TrimPrefix(ref, "#/$defs/")
				}
			}
			rewriteRefs(item, prefix)
		}
	case []any:
		for _, item := range v {
			rewriteRefs(item, prefix)
		}
	}
}
