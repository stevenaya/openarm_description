#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "${ROOT_DIR}/../.." && pwd)"
WORKSPACE_SETUP="${WORKSPACE_DIR}/install/setup.bash"
PACKAGE_SETUP="${ROOT_DIR}/local_setup.bash"
ROS_SETUP="/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash"
PRESET_DIR="${ROOT_DIR}/assets/robot/openarm_v2.0/config/robot_presets"
XACRO_FILE="${ROOT_DIR}/assets/robot/openarm_v2.0/urdf/openarm_v20.urdf.xacro"
OUTPUT_DIR="${ROOT_DIR}/urdf"

COLLAPSE_ARG="true"
PRESET_NAME=""
GRASP_FRAME_ONLY="false"
GENERATE_ALL="false"

source_setup() {
  local setup_file="$1"
  local restore_nounset=0

  if [[ ! -f "${setup_file}" ]]; then
    return 0
  fi

  if [[ $- == *u* ]]; then
    restore_nounset=1
    set +u
  fi

  export COLCON_TRACE="${COLCON_TRACE-}"
  # shellcheck disable=SC1090
  source "${setup_file}"

  if [[ "${restore_nounset}" -eq 1 ]]; then
    set -u
  fi
}

generate_one() {
  local preset_name="$1"
  local emit_grasp="$2"
  local suffix=""
  local output_file=""
  local tmp_file=""

  if [[ "${COLLAPSE_ARG}" == "false" ]]; then
    suffix="${suffix}_no_collapse"
  fi
  if [[ "${emit_grasp}" == "true" ]]; then
    suffix="${suffix}_grasp"
  fi

  output_file="${OUTPUT_DIR}/openarm_${preset_name}${suffix}.urdf"
  tmp_file="$(mktemp "${output_file}.tmp.XXXXXX")"

  if xacro "${XACRO_FILE}" \
    robot_preset:="${preset_name}" \
    collapse_internal_empty_links:="${COLLAPSE_ARG}" \
    emit_grasp_frame:="${emit_grasp}" \
    > "${tmp_file}"; then
    mv "${tmp_file}" "${output_file}"
  else
    rm -f "${tmp_file}"
    return 1
  fi

  echo "Generated ${output_file}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      PRESET_NAME="${2:-}"
      if [[ -z "${PRESET_NAME}" || "${PRESET_NAME}" == --* ]]; then
        echo "Missing value for --preset" >&2
        exit 1
      fi
      shift 2
      ;;
    --grasp-frame)
      GRASP_FRAME_ONLY="true"
      shift
      ;;
    --all)
      GENERATE_ALL="true"
      shift
      ;;
    --keep-empty-links)
      COLLAPSE_ARG="false"
      shift
      ;;
    -o|--output-dir)
      OUTPUT_DIR="${2:-}"
      if [[ -z "${OUTPUT_DIR}" || "${OUTPUT_DIR}" == --* ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage:
  bash ${BASH_SOURCE[0]}
  bash ${BASH_SOURCE[0]} --preset <preset_name> [--grasp-frame] [--keep-empty-links] [--output-dir <dir>]
  bash ${BASH_SOURCE[0]} [--all] [--grasp-frame] [--keep-empty-links] [--output-dir <dir>]

Options:
  --preset <name>     Generate only the selected robot preset.
  --all               Generate every real preset instead of the default dual-arm preset only.
  --grasp-frame       Generate only the grasp-frame variant.
  --keep-empty-links  Disable collapse and keep connection-side empty links.
  -o, --output-dir    Write generated URDF files to the selected directory.

Behavior:
  With no arguments, generate only default_bimanual in both standard and grasp variants.
  With --all, generate all real presets in both standard and grasp variants.
  With --preset only, generate the standard collapsed variant for that preset.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage." >&2
      exit 1
      ;;
  esac
done

if ! command -v xacro >/dev/null 2>&1; then
  source_setup "${ROS_SETUP}"
fi

# xacro includes still rely on package discovery through the ROS 2 environment.
# Source the local workspace/package setup automatically when either exists.
source_setup "${WORKSPACE_SETUP}"
source_setup "${PACKAGE_SETUP}"

if ! command -v xacro >/dev/null 2>&1; then
  echo "xacro command not found. Source ROS 2 first or install the xacro package." >&2
  exit 1
fi

if [[ ! -d "${PRESET_DIR}" ]]; then
  echo "Missing preset directory: ${PRESET_DIR}" >&2
  exit 1
fi

if [[ ! -f "${XACRO_FILE}" ]]; then
  echo "Missing xacro file: ${XACRO_FILE}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

if [[ -n "${PRESET_NAME}" ]]; then
  if [[ ! -f "${PRESET_DIR}/${PRESET_NAME}.yaml" ]]; then
    echo "Unknown preset: ${PRESET_NAME}" >&2
    exit 1
  fi

  generate_one "${PRESET_NAME}" "${GRASP_FRAME_ONLY}"
  exit 0
fi

if [[ "${GRASP_FRAME_ONLY}" == "true" ]]; then
  EMIT_GRASP_VALUES=("true")
else
  EMIT_GRASP_VALUES=("false" "true")
fi

if [[ "${GENERATE_ALL}" == "true" ]]; then
  for preset_file in "${PRESET_DIR}"/*.yaml; do
    preset_name="$(basename "${preset_file}" .yaml)"
    if [[ "${preset_name}" == example_* ]]; then
      continue
    fi
    for emit_grasp in "${EMIT_GRASP_VALUES[@]}"; do
      generate_one "${preset_name}" "${emit_grasp}"
    done
  done
else
  for emit_grasp in "${EMIT_GRASP_VALUES[@]}"; do
    generate_one "default_bimanual" "${emit_grasp}"
  done
fi
