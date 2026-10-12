{
  description = "Cluster administration and automation toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "cluster-admin-shell";

          buildInputs = with pkgs; [
            # Kubernetes & cluster tools
            kubectl
            kubernetes-helm
            k3sup

            # Security & secrets
            sops
            age
            wireguard-tools

            # Ingress & networking
            cloudflared

            # Utilities
            jq
            yq-go
            curl
            git
            shellcheck
          ];

          shellHook = ''
            echo "=========================================================="
            echo " 🚀 Cluster Administration Environment Loaded"
            echo " Tools available: kubectl, helm, k3sup, cloudflared, sops"
            echo "=========================================================="
            export KUBECONFIG="$PWD/.kube/config:$HOME/.kube/config"
          '';
        };
      });
}
