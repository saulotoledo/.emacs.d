#+TITLE: Git Layer
#+CATEGORY: tools
#+PROPERTY: header-args:emacs-lisp :tangle ../../../init.el

* Description
Provides comprehensive Git tooling and version control helpers for Emacs:
- ~magit~: A powerful, keyboard-driven interface for Git.
- ~forge~: GitHub/GitLab issue and pull request integration within Magit.
- ~diff-hl~: Visual diff indicators in the fringe.
- ~blamer~: Inline, contextual Git blame annotations.
- ~ediff~: Side-by-side diffing and merge conflict resolution.
- ~smerge-mode~ & ~conflict-buttons~: Automated merge conflict detection and resolution controls.
- ~git-modes~: Syntax highlighting for ~.gitignore~, ~.gitconfig~, and ~.gitattributes~.
- ~treemacs-magit~: Git status integration inside the Treemacs sidebar.

* Emacs Configuration
** Package: magit
Magit is an interactive Git interface for Emacs.

In the Magit status buffer:
- Press ~!~ to open a command prompt where you can run any git command directly.
- Press ~$~ to open the ~*magit-process*~ buffer showing raw Git process output.

#+begin_src emacs-lisp
(use-package magit
  ;; The :commands directive ensures that magit is not loaded into memory until
  ;; magit-status is explicitly called. This can improve startup performance.
  :commands magit-status)
#+end_src

*** ANSI color support in the magit process buffer

When running Git commands through Magit (e.g., hooks, pre-commit scripts), the
output is displayed in the *magit-process* buffer (accessible by pressing =$= in
the Magit status buffer). This buffer shows the raw output from Git commands.
However, by default, ANSI color codes in the output are not interpreted, so the
output appears with raw escape sequences instead of colored text.

There are two approaches to enable ANSI color support in the Magit process
buffer, and we setup both in this section.

**** Option 1: Official built-in solution (with delay)
The official way to enable ANSI colors is to set
~magit-process-finish-apply-ansi-colors~. However, this only applies colors
after the Git command has finished executing. For slow processes (like
long-running hooks), you'll see the raw escape sequences until the command
completes, which can be distracting.

#+begin_example emacs-lisp
;; Official built-in solution - applies colors after command finishes
(setq magit-process-finish-apply-ansi-colors t)
#+end_example

**** Option 2: Real-time color application (our choice)
A better solution, suggested in [[https://github.com/magit/magit/issues/3549#issuecomment-1375023283][this GitHub comment]], applies colors in real-time
as the buffer is updated. This provides immediate visual feedback without
showing raw escape sequences during long-running commands. This is the approach
we use in our configuration:

#+begin_src emacs-lisp
;; Apply ANSI colors in real-time as the magit-process buffer is updated
(defun cfg-tools/magit-color-buffer (proc &rest _args)
  "Apply ANSI colors to the magit-process buffer in real-time.
PROC is the process object for the magit-process buffer.
_ARGS are additional arguments passed by magit-process-filter (unused)."
  (with-current-buffer (process-buffer proc)
    (read-only-mode -1)
    (ansi-color-apply-on-region (point-min) (point-max))
    (read-only-mode 1)))

(declare-function ansi-color-apply-on-region "ansi-color")
(advice-add 'magit-process-filter :after #'cfg-tools/magit-color-buffer)
#+end_src

** Package: diff-hl
Visual indicators for uncommitted changes in the buffer fringe, synchronized with Magit refreshes.

#+begin_src emacs-lisp
(use-package diff-hl
  :defer t
  :hook ((magit-pre-refresh . ignore)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  (global-diff-hl-mode 1))
#+end_src

** Package: treemacs-magit
Integrates Treemacs with Magit to display Git file status icons in the file tree sidebar.

#+begin_src emacs-lisp
(use-package treemacs-magit
  :after (treemacs magit))
#+end_src

** Package: forge
Forge extends Magit to manage pull requests and issues for GitHub, GitLab, and Bitbucket inside Emacs.

#+begin_src emacs-lisp
(use-package forge
  :pin "MELPA Unstable"
  :after magit)
#+end_src

** Package: blamer
Inline, contextual annotations that display author, date, and commit message directly in your buffer.

#+begin_src emacs-lisp
(use-package blamer
  :demand t
  :custom
  (blamer-type 'both)
  (blamer-idle-time 0.3)
  (blamer-overlay-priority 1) ;; Low priority: ensure completion overlays take precedence
  :custom-face
  (blamer-face ((t :foreground "#5c6370"
                   :background unspecified
                   :height 85))))

(defun cfg-tools/toggle-blamer ()
  "Toggle global-blamer-mode on and off."
  (interactive)
  (global-blamer-mode 'toggle))
#+end_src

** Package: ediff
Built-in interface for comparing and merging files, buffers, and directories.

#+begin_src emacs-lisp
(use-package ediff
  :ensure nil ; Built-in
  :custom
  (ediff-window-setup-function 'ediff-setup-windows-plain) ; Stop floating control panel frame
  (ediff-split-window-function 'split-window-horizontally) ; Split side-by-side
  :config
  ;; When ediff quits without resolving, write back standard git-style markers
  ;; so smerge-mode can detect and re-highlight them in the restored buffer.
  (setq ediff-combination-pattern '("<<<<<<< HEAD" A "=======" B ">>>>>>> other")))
#+end_src

** Package: smerge-mode
The ~smerge-mode~ is a built-in Emacs minor mode designed specifically for
resolving merge conflicts. When you encounter a conflict during a Git merge or
rebase, Emacs can automatically detect the conflict markers (~<<<<<<<~,
~=======~, ~>>>>>>>~) and enable this mode to help you navigate and choose
between changes.

#+begin_src emacs-lisp
(defvar smerge-auto-refine nil)

(defun cfg-tools/smerge-mode-maybe ()
  "Efficiently check for smerge markers in large files.
Only searches the first 10000 characters to prevent lag. For other
cases, rely on Magit or start smerge-mode manually."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^<<<<<<< " 10000 t)
      (smerge-mode 1))))

(use-package smerge-mode
  :ensure nil ; Built-in
  :defer t
  :config
  (set-face-attribute 'smerge-upper nil :background "dark slate blue" :foreground 'unspecified)
  (set-face-attribute 'smerge-lower nil :background "dark olive green" :foreground 'unspecified)
  (set-face-attribute 'smerge-base nil :background "dim gray" :foreground 'unspecified)
  (set-face-attribute 'smerge-refined-removed nil :background "#5a3d3d" :foreground 'unspecified)
  (set-face-attribute 'smerge-refined-added nil :background "#3d5a5a" :foreground 'unspecified)
  (set-face-attribute 'smerge-markers nil :background "#2e2e2e" :foreground "orange")
  (add-hook 'find-file-hook #'cfg-tools/smerge-mode-maybe)
  (add-hook 'after-revert-hook #'cfg-tools/smerge-mode-maybe)
  (setq smerge-auto-refine t))
#+end_src

** Package: conflict-buttons
Add conflict resolution buttons to the buffer.

#+begin_src emacs-lisp
(use-package conflict-buttons
  :defer t
  :hook (smerge-mode . conflict-buttons-mode)
  :init
  ;; Ensure conflict-buttons state survives buffer reverts (revert-buffer).
  ;; If we do not mark the following variable se as permanent-local,
  ;; `kill-all-local-variables' wipes the tracking list, leaving orphaned
  ;; overlays behind.
  (put 'conflict-buttons--overlays 'permanent-local t)
  :config
  ;; Robust sweep: before re-installing buttons, clear ANY existing ones from the buffer
  (advice-add 'conflict-buttons--install :before
              (lambda (&rest _)
                (remove-overlays (point-min) (point-max) 'conflict-buttons t))))
#+end_src

** Package: git-modes
Major modes for editing Git configuration files (~.gitconfig~, ~.gitattributes~, ~.gitignore~) and related ignore files.

#+begin_src emacs-lisp
(use-package git-modes
  :mode (("/\\.gitattributes\\'"  . gitattributes-mode)
         ("/\\.gitconfig\\'"      . gitconfig-mode)
         ("/\\.git/config\\'"     . gitconfig-mode)
         ("/\\.dockerignore\\'"   . gitignore-mode)
         ("/\\.gitignore\\'"      . gitignore-mode)
         ("/\\.npmignore\\'"      . gitignore-mode)
         ("/\\.prettierignore\\'" . gitignore-mode)))
#+end_src

* Keybindings
#+begin_src emacs-lisp
;; --- Global Keybindings via cfg-keys-map ---
(define-key cfg-keys-map (kbd "C-c m") #'magit-status)
(define-key cfg-keys-map (kbd "s-i") #'blamer-show-commit-info)
(define-key cfg-keys-map (kbd "C-c i") #'blamer-show-posframe-commit-info)

;; --- Leader Bindings ---
(cfg-keys/leader-def
  "g g" '(magit-status :whichkey "Magit status")
  "g b" '(cfg-tools/toggle-blamer :whichkey "Toggle inline git blame")
  "g i" '(blamer-show-commit-info :whichkey "Show commit info"))

;; --- Context-Specific Maps ---
(with-eval-after-load 'smerge-mode
  (define-key smerge-mode-map (kbd "C-c M-s-n") #'smerge-next)
  (define-key smerge-mode-map (kbd "C-c M-s-p") #'smerge-prev)
  (define-key smerge-mode-map (kbd "C-c M-s-u") #'smerge-keep-upper)
  (define-key smerge-mode-map (kbd "C-c M-s-l") #'smerge-keep-lower)
  (define-key smerge-mode-map (kbd "C-c M-s-b") #'smerge-keep-base)
  (define-key smerge-mode-map (kbd "C-c M-s-a") #'smerge-keep-all)
  (define-key smerge-mode-map (kbd "C-c M-s-r") #'smerge-resolve)
  (define-key smerge-mode-map (kbd "C-c M-s-E") #'smerge-ediff))
#+end_src

* System Setup
No system setup required.