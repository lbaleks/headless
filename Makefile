BASE ?= http://localhost:3000
.PHONY: getp patchp clearp getc seedc cleanc geto1 getoQ geto patcho syncall

getp:
	curl -s "$(BASE)/api/products/$(SKU)" | jq .

patchp:
	@PRICE_JSON=$$( [ -n "$$PRICE" ] && printf '%s' "$$PRICE" || printf 'null' ); \
	 STATUS_JSON=$$( [ -n "$$STATUS" ] && printf '%s' "$$STATUS" || printf 'null' ); \
	 jq -n --arg name "$$NAME" \
	   --argjson price $$PRICE_JSON \
	   --argjson status $$STATUS_JSON \
	   '({} \
	      + (if $price  != null then {price:$price}   else {} end) \
	      + (if $status != null then {status:$status} else {} end) \
	      + (if $name   != ""   then {name:$name}     else {} end))' \
	| curl -s -X PATCH "$(BASE)/api/products/$(SKU)" -H 'content-type: application/json' --data-binary @- | jq .

clearp:
	@SKU="$(SKU)"; \
	F=var/products.dev.json; tmp=$$(mktemp); \
	if [ -f "$$F" ]; then \
	  jq --arg sku "$$SKU" \
	    '(if type=="array" then map(select(.sku|ascii_downcase != ($$sku|ascii_downcase))) \
	      elif type=="object" and .items then .items = (.items|map(select(.sku|ascii_downcase != ($$sku|ascii_downcase)))) \
	      else . end)' "$$F" > "$$tmp" && mv "$$tmp" "$$F"; \
	fi; \
	curl -s "$(BASE)/api/products/$$SKU" | jq '.sku,.price,.name,.source'

getc:
	curl -s "$(BASE)/api/customers?page=1&size=5" | jq .

seedc:
	curl -s -X DELETE "$(BASE)/api/customers?action=seed&n=$(N)" | jq .

cleanc:
	curl -s -X PATCH  "$(BASE)/api/customers/$(CID)" -H 'content-type: application/json' --data-binary '{"group_id":1,"is_subscribed":false}' | jq .

geto1:
	curl -s "$(BASE)/api/orders?page=1&size=1" | jq .

getoQ:
	curl -s "$(BASE)/api/orders?page=1&size=5&q=$(Q)" | jq .

geto:
	curl -s "$(BASE)/api/orders?page=1&size=5" | jq .

patcho:
	jq -n --arg status "$(STATUS)" '({} + (if $status != "" then {status:$status} else {} end))' \
	| curl -s -X PATCH "$(BASE)/api/orders/$(OID)" -H 'content-type: application/json' --data-binary @- | jq .

syncall:
	bash tools/sync-all.sh "$(BASE)" || true

verify-completeness:
@npm run verify:completeness

smoke:
@npm run smoke
smoke: ; BASE?=http://localhost:3000; BASE=$(BASE) bash tools/smoke.sh
verify: ; npm run verify:all
seed: ; curl -s -X POST 'http://localhost:3000/api/products/seed?n=5' | jq .
export: ; curl -s 'http://localhost:3000/api/products/export' > var/export.csv && echo "→ var/export.csv"
