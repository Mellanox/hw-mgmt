# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

# Do not use set -euo pipefail here: this file is sourced into the user shell.

_hw_management()
{
	local cur cword cmds

	cmds="start stop chipup chipdown chipupen chipupdis thermsuspend thermresume restart force-reload reset-cause"

	if declare -F _init_completion >/dev/null 2>&1; then
		_init_completion || return
	else
		COMPREPLY=()
		cur="${COMP_WORDS[COMP_CWORD]}"
		cword=$COMP_CWORD
	fi

	# Only the first argument (action name). Extra args are not completed.
	if [[ $cword -eq 1 ]]; then
		COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
		return 0
	fi

	COMPREPLY=()
	return 0
} &&
complete -F _hw_management hw-management.sh

# ex: filetype=sh
