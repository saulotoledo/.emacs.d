;;; init-bootstrap.el --- Personal bootstraping file -*- lexical-binding: t; -*-

;;; Commentary:

;; Rename this file to init.el. It will replace itself with the
;; actual configuration at first run.
;; We could use `git update-index --assume-unchanged init.el`, but
;; I find it easier to rename it.

;;; Code:

(require 'org)
(find-file (concat user-emacs-directory "init.org"))
(org-babel-tangle)
(load-file (concat user-emacs-directory "init.el"))

;; The following line is not necessary in Emacs 28+, because it
;; generates native compilation files (.eln) instead of .elc:
;; (byte-compile-file (concat user-emacs-directory "init.el"))
;; We use native compilation instead:
(setq native-comp-jit-compilation t)
(native-compile-async (concat user-emacs-directory "init.el"))
;;; init-bootstrap.el ends here
