#!/usr/bin/env bash
# git-teams.sh — transférer une branche de ticket sur plusieurs dépôts en UNE archive (via Teams)
set -euo pipefail

ROOT="${ROOT:-$HOME/projets}"    # dossier qui contient tes dépôts
REPOS=(repo1 repo2 repo3 repo4)  # ⚠️ remplace par les noms de tes 4 dépôts
OUT="${OUT:-$HOME/Downloads}"    # où les archives sont créées / téléchargées
BASE="${BASE:-origin/develop}"   # branche de départ des tickets
PREFIX="feature/"

cmd=${1:-}; key=${2:-}; archive=${3:-}
branch="$PREFIX$key"

usage() {
  cat <<EOF
  init                     PC1, une fois : archive complète des dépôts -> init.tgz
  clone [archive]          PC2, une fois : clone les dépôts depuis init.tgz
  start PROJ-123           PC1 : crée les worktrees du ticket + l'archive à envoyer
  pack  PROJ-123           crée l'archive du ticket (PC1 ou PC2) -> PROJ-123.tgz
  unpack PROJ-123 [archive]  applique l'archive reçue (PC1 ou PC2)
  publish PROJ-123         PC1 : pousse la branche sur origin
EOF
  exit 1
}
[ -n "$cmd" ] || usage
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# worktree où la branche est extraite (vide sinon)
worktree_of() {
  git worktree list --porcelain | awk -v b="branch refs/heads/$branch" \
    '/^worktree /{p=substr($0,10)} $0==b{print p}'
}

case "$cmd" in
  init)
    for r in "${REPOS[@]}"; do
      git -C "$ROOT/$r" bundle create "$tmp/$r.bundle" --all
    done
    tar -czf "$OUT/init.tgz" -C "$tmp" .
    echo "✅ Envoie $OUT/init.tgz via Teams" ;;

  clone)
    tar -xzf "${key:-$OUT/init.tgz}" -C "$tmp"
    for r in "${REPOS[@]}"; do git clone -q "$tmp/$r.bundle" "$ROOT/$r"; done
    echo "✅ ${#REPOS[@]} dépôts clonés dans $ROOT" ;;

  start|pack)
    [ -n "$key" ] || usage
    for r in "${REPOS[@]}"; do
      cd "$ROOT/$r"
      if [ "$cmd" = start ]; then
        git fetch -q origin
        git worktree add -q "$ROOT/$r-$key" -b "$branch" "$BASE"
      fi
      if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
        git bundle create -q "$tmp/$r.bundle" "$branch"
      else
        echo "   (pas de $branch dans $r, ignoré)"
      fi
    done
    tar -czf "$OUT/$key.tgz" -C "$tmp" .
    echo "✅ Envoie $OUT/$key.tgz via Teams" ;;

  unpack)
    [ -n "$key" ] || usage
    tar -xzf "${archive:-$OUT/$key.tgz}" -C "$tmp"
    for r in "${REPOS[@]}"; do
      [ -f "$tmp/$r.bundle" ] || continue
      echo "== $r"
      cd "$ROOT/$r"
      git fetch -q "$tmp/$r.bundle" "$branch"
      wt=$(worktree_of)
      if [ -z "$wt" ]; then
        wt="$ROOT/$r-$key"
        if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
          git worktree add -q "$wt" "$branch"
        else
          git worktree add -q "$wt" -b "$branch" FETCH_HEAD; continue
        fi
      fi
      git -C "$wt" merge -q --ff-only FETCH_HEAD \
        || { echo "❌ $r : modifs non commitées ou branche divergente"; exit 1; }
    done
    echo "✅ $branch à jour" ;;

  publish)
    for r in "${REPOS[@]}"; do
      git -C "$ROOT/$r" rev-parse -q --verify "refs/heads/$branch" >/dev/null \
        && git -C "$ROOT/$r" push -u origin "$branch"
    done ;;

  *) usage ;;
esac
