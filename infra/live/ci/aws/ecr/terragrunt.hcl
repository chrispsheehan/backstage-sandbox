include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules//aws//ecr"
}

inputs = {
  # Preserve the dev repository suffix; the module prefixes account and region.
  base_name = "backstage-sandbox-dev"
}
