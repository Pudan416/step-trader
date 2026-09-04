#!/bin/zsh

set -u

if (( $# < 3 )); then
  print -u2 'usage: run-heavy.sh <label> <zero|nonzero> <command> [args...]'
  exit 64
fi

label="$1"
expected_exit="$2"
shift 2

case "$expected_exit" in
  zero|nonzero) ;;
  *)
    print -u2 "invalid expected-exit mode: $expected_exit"
    exit 64
    ;;
esac

director_root='artifacts/day-objects-editorial-field/director/task-1b-3e5f309-attempt5'
command_root="$director_root/commands/$label"

if [[ -e "$command_root" ]]; then
  print -u2 "immutable command evidence already exists: $command_root"
  exit 65
fi

mkdir -p "$command_root"

command_text=''
for argument in "$@"; do
  command_text+="${(q)argument} "
done
command_text="${command_text% }"

started_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
started_epoch="$(date '+%s')"

{
  printf 'label=%s\n' "$label"
  printf 'expected_exit=%s\n' "$expected_exit"
  printf 'working_directory=%s\n' "$PWD"
  printf 'source_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
  printf 'command=%s\n' "$command_text"
} > "$command_root/command.txt"

{
  printf 'sample=prelaunch\n'
  printf 'utc=%s\n' "$started_utc"
  /usr/sbin/sysctl vm.swapusage
  /usr/bin/vm_stat | rg 'Pages free|Pages throttled|Swapins|Swapouts'
} > "$command_root/resource-baseline.log"

baseline_swapouts="$(/usr/bin/vm_stat | awk '/Swapouts/ {gsub(/\./,"",$2); print $2}')"
baseline_throttled="$(/usr/bin/vm_stat | awk '/Pages throttled/ {gsub(/\./,"",$3); print $3}')"

{
  printf 'status=RUNNING\n'
  printf 'started_utc=%s\n' "$started_utc"
  printf 'baseline_swapouts=%s\n' "$baseline_swapouts"
  printf 'baseline_pages_throttled=%s\n' "$baseline_throttled"
} > "$command_root/exit.txt"

: > "$command_root/resource-monitor.log"

/usr/bin/time -l "$@" > "$command_root/output.log" 2>&1 &
command_pid=$!
printf 'command_pid=%s\n' "$command_pid" >> "$command_root/exit.txt"

resource_breach=0
breach_reason='none'

while kill -0 "$command_pid" 2>/dev/null; do
  sample_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  current_swapouts="$(/usr/bin/vm_stat | awk '/Swapouts/ {gsub(/\./,"",$2); print $2}')"
  current_throttled="$(/usr/bin/vm_stat | awk '/Pages throttled/ {gsub(/\./,"",$3); print $3}')"
  {
    printf 'sample_begin\n'
    printf 'utc=%s\n' "$sample_utc"
    /usr/sbin/sysctl vm.swapusage
    /usr/bin/vm_stat | rg 'Pages free|Pages throttled|Swapins|Swapouts'
    printf 'sample_end\n'
  } >> "$command_root/resource-monitor.log"

  if (( current_swapouts > baseline_swapouts )); then
    resource_breach=1
    breach_reason="swapouts_increased_${baseline_swapouts}_to_${current_swapouts}"
  elif (( current_throttled != 0 )); then
    resource_breach=1
    breach_reason="pages_throttled_nonzero_${current_throttled}"
  fi

  if (( resource_breach != 0 )); then
    child_pid="$(pgrep -P "$command_pid" | head -n 1)"
    if [[ -n "$child_pid" ]]; then
      kill -INT "$child_pid" 2>/dev/null || true
    fi
    break
  fi

  sleep 10
done

wait "$command_pid"
actual_exit=$?

ended_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ended_epoch="$(date '+%s')"
duration_seconds=$(( ended_epoch - started_epoch ))

{
  printf 'sample=postexit\n'
  printf 'utc=%s\n' "$ended_utc"
  /usr/sbin/sysctl vm.swapusage
  /usr/bin/vm_stat | rg 'Pages free|Pages throttled|Swapins|Swapouts'
} > "$command_root/resource-end.log"

end_swapouts="$(/usr/bin/vm_stat | awk '/Swapouts/ {gsub(/\./,"",$2); print $2}')"
end_throttled="$(/usr/bin/vm_stat | awk '/Pages throttled/ {gsub(/\./,"",$3); print $3}')"
swapouts_delta=$(( end_swapouts - baseline_swapouts ))
process_swaps="$(rg '^[[:space:]]+[0-9]+[[:space:]]+swaps$' "$command_root/output.log" | tail -n 1 | awk '{print $1}')"
if [[ -z "$process_swaps" ]]; then
  process_swaps='unavailable'
fi

expected_exit_met=0
if [[ "$expected_exit" == zero && "$actual_exit" == 0 ]]; then
  expected_exit_met=1
elif [[ "$expected_exit" == nonzero && "$actual_exit" != 0 ]]; then
  expected_exit_met=1
fi

if (( swapouts_delta != 0 )) || (( end_throttled != 0 )); then
  resource_breach=1
  if [[ "$breach_reason" == none ]]; then
    breach_reason="postexit_swapouts_delta_${swapouts_delta}_throttled_${end_throttled}"
  fi
fi
if [[ "$process_swaps" != 0 ]]; then
  resource_breach=1
  if [[ "$breach_reason" == none ]]; then
    breach_reason="process_swaps_${process_swaps}"
  fi
fi

{
  printf 'status=COMPLETE\n'
  printf 'actual_exit=%s\n' "$actual_exit"
  printf 'expected_exit_met=%s\n' "$expected_exit_met"
  printf 'ended_utc=%s\n' "$ended_utc"
  printf 'duration_seconds=%s\n' "$duration_seconds"
  printf 'resource_breach=%s\n' "$resource_breach"
  printf 'breach_reason=%s\n' "$breach_reason"
  printf 'end_swapouts=%s\n' "$end_swapouts"
  printf 'swapouts_delta=%s\n' "$swapouts_delta"
  printf 'end_pages_throttled=%s\n' "$end_throttled"
  printf 'process_swaps=%s\n' "$process_swaps"
} >> "$command_root/exit.txt"

shasum -a 256 \
  "$command_root/command.txt" \
  "$command_root/output.log" \
  "$command_root/exit.txt" \
  "$command_root/resource-baseline.log" \
  "$command_root/resource-monitor.log" \
  "$command_root/resource-end.log" \
  > "$command_root/SHA256SUMS"

printf 'label=%s actual_exit=%s expected_exit_met=%s duration_seconds=%s swapouts_delta=%s pages_throttled=%s process_swaps=%s resource_breach=%s\n' \
  "$label" "$actual_exit" "$expected_exit_met" "$duration_seconds" "$swapouts_delta" "$end_throttled" "$process_swaps" "$resource_breach"

if (( expected_exit_met == 0 )) || (( resource_breach != 0 )); then
  exit 1
fi
exit 0
