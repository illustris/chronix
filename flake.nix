{
	description = "ChroNix - NixOS Configuration Change Tracker";

	outputs = { self, nixpkgs }: with nixpkgs.lib; let
		archs = [
			"x86_64-linux"
			"aarch64-linux"
			"riscv64-linux"
		];
	in {
		packages = genAttrs archs (system: with nixpkgs.legacyPackages.${system}; rec {
			chronix = writeScriptBin "chronix" (builtins.readFile ./chronix);
			default = chronix;
		});

		nixosModules.chronix = { config, pkgs, lib, ... }: with lib; {
			options.services.chronix = {
				kafka = {
					enable = mkEnableOption "chronix kafka producer";
					brokers = mkOption {
						type = types.str;
					};
					topic = mkOption {
						type = types.str;
					};
				};
				prometheus.enable = mkEnableOption "chronix prometheus textfile generation";
			};

			config = let
				cfg = config.services.chronix;
			in {
				services.prometheus.exporters.node.extraFlags = mkIf cfg.prometheus.enable [
					"--collector.textfile.directory=/run/chronix"
				];

				systemd = mkIf (cfg.kafka.enable || cfg.prometheus.enable) {
					services.chronix = {
						wantedBy = [ "multi-user.target" ];
						after = [ "network.target" ];
						path = with pkgs; [
							self.packages.${pkgs.system}.chronix
							nettools jq diffutils inotify-tools
						] ++ (optionals (cfg.kafka.enable) [
							kcat
						]);
						environment = {
							inherit (config.system.nixos) release codeName;
						};
						script = concatStringsSep " " [
							"chronix"
							(optionalString cfg.kafka.enable "-b ${cfg.kafka.brokers} -t ${cfg.kafka.topic}")
							(optionalString cfg.prometheus.enable "--prom")
						];
						serviceConfig = {
							Type = "simple";
							Restart = "on-failure";
						};
					};
					tmpfiles.rules = [
						"d /run/chronix 755 root root"
					];
				};
			};
		};
	};
}
