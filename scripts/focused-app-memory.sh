#!/usr/bin/env bash

set -euo pipefail

frontmost_app_info="$(
  osascript -l JavaScript <<'JXA'
ObjC.import('AppKit')

function run() {
  const app = $.NSWorkspace.sharedWorkspace.frontmostApplication
  if (!app) {
    throw new Error('Unable to resolve the frontmost application.')
  }

  const pid = Number(app.processIdentifier)
  const name = ObjC.unwrap(app.localizedName) || 'Unknown'
  const bundleID = ObjC.unwrap(app.bundleIdentifier) || 'Unknown'

  return [pid, name, bundleID].join('\t')
}
JXA
)"

if [[ -z "${frontmost_app_info}" ]]; then
  echo "Unable to resolve the frontmost application." >&2
  exit 1
fi

IFS=$'\t' read -r root_pid app_name bundle_id <<< "${frontmost_app_info}"
inspector_pid="$$"

if [[ -z "${root_pid}" ]]; then
  echo "Unable to resolve the frontmost application PID." >&2
  exit 1
fi

process_report="$(
  ps -axo pid=,ppid=,rss=,command= | awk -v root_pid="${root_pid}" -v exclude_pid="${inspector_pid}" '
    function push(pid) {
      if (pid == "" || seen[pid]) {
        return
      }

      seen[pid] = 1
      queue[++queue_tail] = pid
    }

    BEGIN {
      FS = "[[:space:]]+"
      queue_head = 1
      queue_tail = 0
      exclude_head = 1
      exclude_tail = 0
    }

    {
      pid = $1
      ppid = $2
      rss = $3

      $1 = ""
      $2 = ""
      $3 = ""
      sub(/^[[:space:]]+/, "", $0)

      parent[pid] = ppid
      memory_kb[pid] = rss + 0
      command[pid] = $0
      children[ppid] = children[ppid] " " pid
    }

    END {
      if (!(root_pid in parent)) {
        exit 2
      }

      if (exclude_pid in parent) {
        excluded[exclude_pid] = 1
        excluded_queue[++exclude_tail] = exclude_pid

        while (exclude_head <= exclude_tail) {
          excluded_current = excluded_queue[exclude_head++]
          split(children[excluded_current], excluded_child_list, " ")

          for (excluded_index in excluded_child_list) {
            excluded_child = excluded_child_list[excluded_index]
            if (excluded_child != "" && !excluded[excluded_child]) {
              excluded[excluded_child] = 1
              excluded_queue[++exclude_tail] = excluded_child
            }
          }
        }
      }

      push(root_pid)

      while (queue_head <= queue_tail) {
        current = queue[queue_head++]
        split(children[current], child_list, " ")

        for (child_index in child_list) {
          child = child_list[child_index]
          if (child != "") {
            push(child)
          }
        }
      }

      for (pid in seen) {
        if (excluded[pid]) {
          continue
        }

        total_kb += memory_kb[pid]
        print pid "\t" parent[pid] "\t" memory_kb[pid] "\t" command[pid]
      }

      print "TOTAL\t" total_kb
    }
  '
)"

if [[ -z "${process_report}" ]]; then
  echo "No process information found for PID ${root_pid}." >&2
  exit 1
fi

process_rows="$(printf '%s\n' "${process_report}" | grep -v '^TOTAL	' | sort -t $'\t' -k3,3nr)"
total_kb="$(printf '%s\n' "${process_report}" | awk -F '\t' '$1 == "TOTAL" { print $2 }')"

if [[ -z "${total_kb}" ]]; then
  echo "Failed to compute total memory for PID ${root_pid}." >&2
  exit 1
fi

format_kib() {
  awk -v kib="$1" '
    function abs(value) {
      return value < 0 ? -value : value
    }

    BEGIN {
      if (kib >= 1048576) {
        printf "%.2f GiB", kib / 1048576
      } else if (kib >= 1024) {
        printf "%.2f MiB", kib / 1024
      } else {
        printf "%d KiB", kib
      }
    }
  '
}

printf 'Focused app: %s\n' "${app_name}"
printf 'Bundle ID: %s\n' "${bundle_id}"
printf 'Root PID: %s\n' "${root_pid}"
printf 'Total RSS (root + descendants, excluding this inspector subtree): %s\n' "$(format_kib "${total_kb}")"
printf '\n'
printf '%-8s %-8s %-14s %s\n' "PID" "PPID" "RSS" "COMMAND"

while IFS=$'\t' read -r pid ppid rss command; do
  [[ -z "${pid}" ]] && continue
  printf '%-8s %-8s %-14s %s\n' "${pid}" "${ppid}" "$(format_kib "${rss}")" "${command}"
done <<< "${process_rows}"
