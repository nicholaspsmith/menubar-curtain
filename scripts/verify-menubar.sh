#!/usr/bin/env bash
# Report what the menu bar looks like and flag anything stranded.
# Needs Accessibility for whichever terminal runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift scripts/verify-menubar.swift
