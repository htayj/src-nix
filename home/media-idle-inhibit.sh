# Discord keeps a running browser audio stream even when it is silent. The
# PipeWire inhibitor cannot filter media.name, so gate its lifetime on eligible
# streams here, including when a video and Discord share the same Firefox app.
inhibitor_pid=

stop_inhibitor() {
  if [[ -n "$inhibitor_pid" ]]; then
    kill "$inhibitor_pid" 2>/dev/null || true
    wait "$inhibitor_pid" 2>/dev/null || true
    inhibitor_pid=
    echo "Released media idle inhibitor: no eligible playback"
  fi
}

trap stop_inhibitor EXIT
trap 'exit 0' TERM INT

while true; do
  # A failed audio query must release the inhibitor, not leave it stuck on.
  # Pipe, not a here-string: bash spools a large here-string to a disk file.
  eligible=$(timeout 10 pw-dump | jq '
    any(.[];
      .type == "PipeWire:Interface:Node"
      and .info.state == "running"
      and .info.props["media.class"] == "Stream/Output/Audio"
      and ((.info.props["media.role"] // "")
        | test("^(Communication|Notification)$"; "i") | not)
      and ((.info.props["application.name"] // "")
        | test("^(Discord|Vesktop|WebCord)$"; "i") | not)
      and ((.info.props["media.name"] // "")
        | test("^([(][0-9]+[)] )?Discord( [|]|$)"; "i") | not)
    )
  ')

  if [[ "$eligible" == true ]]; then
    if [[ -z "$inhibitor_pid" ]]; then
      echo "Eligible playback detected: starting media idle inhibitor"
      wayland-pipewire-idle-inhibit --idle-inhibitor d-bus \
        --media-minimum-duration 5 --verbosity INFO "$@" &
      inhibitor_pid=$!
    elif ! kill -0 "$inhibitor_pid" 2>/dev/null; then
      echo "Media idle inhibitor exited unexpectedly" >&2
      exit 1
    fi
  else
    stop_inhibitor
  fi
  sleep 2
done
