# Product

## Register

product

## Users

i2Message is for macOS users who rely on Messages throughout the day and want a native client that is faster, easier to search, and more stable under large histories than Messages.app. Primary users keep years of conversations, switch between many active threads, need keyboard-first navigation, and expect privacy-preserving local processing.

## Product Purpose

The product provides a modern native macOS Messages/iMessage client with complete Messages.app parity where technically possible. It should load quickly, page through long transcripts without jank, search exact matches immediately, offer local semantic search over message history, show contacts and attachments clearly, and keep all message data local unless the user explicitly opts into a future external capability.

Success means a fresh build launches into a polished mock inbox, real data workers can plug into stable shared contracts, and future production builds can request the required macOS permissions without changing the foundation.

## Brand Personality

Calm, fast, precise.

The interface should feel like a serious macOS productivity tool: familiar enough to trust immediately, more refined than Messages.app under load, and quiet enough to live beside work apps all day.

## Anti-references

- Electron/Tauri-style shells that feel web-wrapped or ignore native macOS behavior.
- Decorative glassmorphism, gradient text, giant rounded marketing cards, and oversized hero layouts.
- Chat apps that hide controls behind novelty interactions or make search feel modal and slow.
- Dense developer tools that expose implementation detail instead of conversation context.
- Any UI that implies cloud processing for private message content by default.

## Design Principles

1. Native first: use SwiftUI, SF typography, macOS navigation, menus, focus, keyboard, accessibility, and system materials where they serve the task.
2. Speed is visible: long histories, search, pagination, and loading states should make progress obvious without blocking the main conversation workflow.
3. Privacy is structural: local processing is the default architecture, not a settings footnote.
4. Parity with judgment: match Messages.app capabilities where possible, and make unsupported macOS capabilities explicit through typed errors and honest UI states.
5. Quiet control: keep the product restrained, legible, and consistent so users can scan, compare, and act repeatedly.

## Accessibility & Inclusion

Target WCAG 2.2 AA for contrast and interaction states. Every interactive control should have a VoiceOver label, keyboard access, a clear focus state, and reduced-motion alternatives. Text must fit at small macOS window sizes and larger accessibility text settings. Search, pagination, and empty states should be understandable without relying only on color.
