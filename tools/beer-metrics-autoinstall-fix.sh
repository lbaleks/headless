#!/usr/bin/env bash
set -euo pipefail
find_group_id(){
 local setId="$1" wanted="${2:-General}"
 local groups gid
 groups="$(curl -sS -H "Authorization: Bearer $JWT" "$V1/products/attribute-sets/$setId/groups")"
 gid="$(jq -re '.[]?|select(.attribute_group_name=="'"$wanted"'")?.attribute_group_id'<<<"$groups"2>/dev/null||true)"
 if [[ -z "$gid"||"$gid"=="null" ]];then gid="$(jq -re '.[0]?.attribute_group_id'<<<"$groups"2>/dev/null||true)";fi
 if [[ -z "$gid"||"$gid"=="null" ]];then echo "❌ Ingen groupId for $setId">&2;exit 1;fi
 echo "$gid"
}
echo "✓ Patch klar. Sett LC_ALL=C og kall find_group_id i scriptet ditt."
