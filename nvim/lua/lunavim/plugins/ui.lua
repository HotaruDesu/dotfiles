local specs = {}

for _, module in ipairs {
  "lunavim.ui_specs.theme",
  "lunavim.ui_specs.chrome",
  "lunavim.ui_specs.notifications",
  "lunavim.ui_specs.snacks",
  "lunavim.ui_specs.extras",
} do
  vim.list_extend(specs, require(module))
end

return specs
