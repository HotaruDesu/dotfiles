return {
  {
    "dmtrKovalenko/fff",
    version = "v0.11.0",
    lazy = true,
    -- Search adapters load the library without replacing the Snacks interface.
    -- Installation/build is explicit; normal searches never download binaries.
    build = function()
      require("fff.download").download_or_build_binary()
    end,
  },
}
