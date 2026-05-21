{ self, lib }:

let
  coding-agent = import ./coding-agent/lib.nix { inherit self lib; };
in
{
  inherit (coding-agent) mkCodingAgent;
}
