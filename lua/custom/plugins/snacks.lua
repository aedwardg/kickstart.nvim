-- snacks.image: image files open as images, and images in markdown render
-- inline. Draws with the Kitty graphics protocol's Unicode placeholders.
-- Only the image module is enabled.
return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  init = function()
    -- Rex supports Kitty graphics with Unicode placeholders, but snacks.image
    -- only recognizes kitty, Ghostty and WezTerm by name (Rex answers XTVERSION
    -- with "rex ..."). Treat Rex like Ghostty unless told otherwise.
    if vim.env.TERM_PROGRAM == 'rex' and vim.env.SNACKS_GHOSTTY == nil then
      vim.env.SNACKS_GHOSTTY = 'true'
    end
  end,
  ---@type snacks.Config
  opts = {
    image = { enabled = true },
  },
}
