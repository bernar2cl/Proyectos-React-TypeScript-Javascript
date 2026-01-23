#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Iniciando sincronización de submódulos..."

# Opcional: cambiar branch target si no quieres 'main'
TARGET_BRANCH="main"
REMOTE_NAME="origin"

# Asegúrate de estar en la raíz del repo (donde está .gitmodules)
if [ ! -f ".gitmodules" ]; then
  echo "❌ No encontré .gitmodules en la carpeta actual. Ejecuta este script desde la raíz del repo principal."
  exit 1
fi

# 1) Actualizar referencias remotas de cada submódulo
echo "📡 Actualizando refs remotas de submódulos (fetch + merge remoto)..."
git submodule foreach --quiet '
  echo "  ↳ $name: entrando..."
  # intenta obtener cambios remotos y mergearlos según la rama principal del submódulo
  # obtiene la rama actual del submódulo
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    # Si no hay branch (detached HEAD), intenta usar main/master por defecto
    if git show-ref --verify --quiet refs/heads/main; then
      branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      branch="master"
    else
      echo "    ⚠️ No detecté branch para $name. Se omite update --remote."
      exit 0
    fi
  fi

  # fetch y actualizar remoto para la rama detectada
  echo "    ➤ Branch detectada: $branch"
  git fetch '"$REMOTE_NAME"' || git fetch --all || true
  # intenta mergear la rama remota si existe
  if git ls-remote --exit-code '"$REMOTE_NAME"' refs/heads/"$branch" >/dev/null 2>&1; then
    git merge --ff-only '"$REMOTE_NAME"'/"$branch" || git merge --no-edit '"$REMOTE_NAME"'/"$branch" || true
  else
    echo "    ⚠️ No existe ${REMOTE_NAME}/${branch} remoto. Se salta el merge remoto."
  fi
'

# Alternativa/Extra: fuerza actualizar todas las referencias al último commit remoto de su rama configurada
# (descomenta la línea de abajo si prefieres esto en vez de la lógica previa)
# git submodule update --remote --merge

# 2) Recorremos submódulos para hacer commit/push si hay cambios locales en cada submódulo
echo "📝 Comprobando cambios en cada submódulo y empujando si corresponde..."
git submodule foreach --quiet '
  echo "  ↳ $name: comprobando cambios..."
  # Si hay cambios (staged o unstaged), commitéalos y pushéalos
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git add -A
    # evita commits vacíos
    if ! git diff --cached --quiet; then
      git commit -m "Auto: actualización dentro del submódulo $name"
      # intenta conocer la rama actual
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
      if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        branch="main"
      fi
      # push seguro: si no existe upstream intenta crearlo
      if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
        git push '"$REMOTE_NAME"' "$branch"
      else
        git push -u '"$REMOTE_NAME"' "$branch" || git push '"$REMOTE_NAME"' "$branch" || true
      fi
    fi
  else
    echo "    ✅ Sin cambios en $name"
  fi
'

# 3) Volver al repo raíz: actualizar la referencia de cada submódulo (pointer) si cambió
echo "📦 Actualizando referencias en repo principal..."
# Añadimos los submódulos que hayan cambiado (git add detecta carpetas con nuevo commit pointer)
git add -A

# Solo commit si hay cambios en el índice del repo raíz
if ! git diff --cached --quiet; then
  git commit -m "Auto: actualización de referencias de submódulos"
  # intenta push a la rama target
  current_branch="$(git rev-parse --abbrev-ref HEAD || echo "$TARGET_BRANCH")"
  echo "    ➤ Repo raíz en branch $current_branch -> push ${REMOTE_NAME}/${current_branch}"
  git push "$REMOTE_NAME" "$current_branch"
else
  echo "✅ Referencias del repo principal sin cambios."
fi

echo "🎉 Sincronización completada."
