local lsp = require("lspconfig")

lsp.just.setup({})

return {
	"jellydn/hurl.nvim",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
	},
	ft = "hurl", -- load for .hurl files
	opts = {},
	keys = {
		-- Run API request
		{ "<leader>hA", "<cmd>HurlRunner<CR>", desc = "Run All requests" },
		{ "<leader>ha", "<cmd>HurlRunnerAt<CR>", desc = "Run Api request" },
		{ "<leader>hte", "<cmd>HurlRunnerToEntry<CR>", desc = "Run Api request to entry" },
		{ "<leader>htE", "<cmd>HurlRunnerToEnd<CR>", desc = "Run Api request from current entry to end" },
		{ "<leader>htm", "<cmd>HurlToggleMode<CR>", desc = "Hurl Toggle Mode" },
		{ "<leader>htv", "<cmd>HurlVerbose<CR>", desc = "Run Api in verbose mode" },
		{ "<leader>htV", "<cmd>HurlVeryVerbose<CR>", desc = "Run Api in very verbose mode" },
	},
}
