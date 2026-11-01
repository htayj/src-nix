{ config, pkgs, ... }:
let
  state = "${config.xdg.dataHome}/local-telemetry";
  tempoConfig = pkgs.writeText "tempo-local.yaml" ''
    server:
      http_listen_address: 127.0.0.1
      http_listen_port: 3200
      grpc_listen_address: 127.0.0.1
      grpc_listen_port: 9095
    memberlist:
      bind_addr: [127.0.0.1]
      bind_port: 7946
      advertise_addr: 127.0.0.1
    usage_report:
      reporting_enabled: false
    distributor:
      receivers:
        otlp:
          protocols:
            http:
              endpoint: 127.0.0.1:4318
    backend_worker:
      compaction:
        block_retention: 720h
    backend_scheduler:
      local_work_path: ${state}/tempo/scheduler
      provider:
        compaction:
          compaction:
            block_retention: 720h
    storage:
      trace:
        backend: local
        local:
          path: ${state}/tempo/blocks
        wal:
          path: ${state}/tempo/wal
    live_store:
      shutdown_marker_dir: ${state}/tempo/live-store/shutdown-marker
      wal:
        path: ${state}/tempo/live-store/wal
    block_builder:
      wal:
        path: ${state}/tempo/block-builder/wal
  '';
  provisioning = pkgs.runCommand "grafana-local-provisioning" {} ''
    mkdir -p $out/{datasources,plugins,dashboards,alerting}
    cat > $out/datasources/tempo.yaml <<'EOF'
    apiVersion: 1
    datasources:
      - name: Local Tempo
        uid: local-tempo
        type: tempo
        access: proxy
        url: http://127.0.0.1:3200
        isDefault: true
        editable: false
    EOF
  '';
  plugins = pkgs.linkFarm "grafana-local-plugins" [
    { name = "tempo"; path = pkgs.grafanaPlugins.tempo; }
  ];
  grafanaConfig = pkgs.writeText "grafana-local.ini" ''
    [paths]
    data = ${state}/grafana
    logs = ${state}/grafana/log
    plugins = ${plugins}
    provisioning = ${provisioning}
    [server]
    http_addr = 127.0.0.1
    http_port = 3000
    domain = localhost
    [analytics]
    reporting_enabled = false
    check_for_updates = false
    check_for_plugin_updates = false
    feedback_links_enabled = false
    [security]
    disable_initial_admin_creation = true
    [auth]
    disable_login_form = true
    [auth.basic]
    enabled = false
    [auth.anonymous]
    enabled = true
    org_role = Viewer
    [users]
    allow_sign_up = false
    # Permit Explore without permission to save dashboards or change datasources.
    viewers_can_edit = true
    [plugins]
    preinstall_disabled = true
  '';
in {
  systemd.user.services.tempo = {
    Unit.Description = "Local Tempo trace storage";
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.tempo}/bin/tempo -config.file=${tempoConfig}";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${state}/tempo";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
    };
  };
  systemd.user.services.grafana = {
    Unit = {
      Description = "Local Grafana trace viewer";
      After = [ "tempo.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.grafana}/bin/grafana server --homepath ${pkgs.grafana}/share/grafana --config ${grafanaConfig}";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${state}/grafana";
      WorkingDirectory = "${pkgs.grafana}/share/grafana";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
    };
  };
}
