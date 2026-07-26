;;; retangle.el --- Retangle init.org into init files -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Expand layer includes from init.org and tangle init.el, early-init.el,
;; and setup.sh. Usable interactively or from the shell:
;;
;;   `emacs --batch -Q -l ~/.emacs.d/retangle.el -f cfg-core/retangle-init
;;
;; Optional native-compile after tangle:
;;
;;   `emacs --batch -Q -l ~/.emacs.d/retangle.el \
;;     --eval '(cfg-core/retangle-init t)'
;;
;;; Code:

(require 'cl-lib)

(declare-function org-babel-tangle "ob-tangle")
(declare-function org-babel-effective-tangled-filename "ob-tangle")
(declare-function org-export-expand-include-keyword "ox")
(declare-function org-set-regexps-and-options "org")
(declare-function native-compile "comp")
(declare-function native-compile-async "comp")

(defconst cfg-core--layer-default-priority 100
  "Fallback priority when a category PRIORITY file or layer keyword is absent.")

(defvar cfg-core--retangling nil
  "Non-nil while `cfg-core/retangle-init' is running.
Prevents after-save recursion if a layer/manifest write retriggers the hook.")

;;; Paths

(defun cfg-core/--emacs-dir ()
  "Return `user-emacs-directory' as a directory file name."
  (file-name-as-directory
   (or (bound-and-true-p user-emacs-directory)
       (expand-file-name "~/.emacs.d/"))))

(defun cfg-core/--layers-dir ()
  "Return the absolute path of the layers/ directory."
  (expand-file-name "layers" (cfg-core/--emacs-dir)))

(defun cfg-core/--layers-manifest ()
  "Return the absolute path of layers/README.org."
  (expand-file-name "README.org" (cfg-core/--layers-dir)))

(defun cfg-core/--init-org ()
  "Return the absolute path of init.org."
  (expand-file-name "init.org" (cfg-core/--emacs-dir)))

(defun cfg-core/--setup-script-org ()
  "Return the absolute path of setup-script.org."
  (expand-file-name "setup-script.org" (cfg-core/--emacs-dir)))

(defun cfg-core/--retangle-work-org ()
  "Return a work-buffer path used only during expand/tangle.
Same directory as init.org (for relative #+INCLUDE resolution) but never
the real init.org path, so `find-file'/save cannot collide with it."
  (expand-file-name ".retangle-work.org" (cfg-core/--emacs-dir)))

(defun cfg-core/--layer-path-parts (file layers-dir)
  "Split FILE's path relative to LAYERS-DIR into directory components."
  (split-string (file-relative-name file layers-dir) "/" t))

;;; Layer discovery -- scan / priority / sort

(defun cfg-core/--layer-readme-files (layers-dir)
  "Return absolute paths of layers/*/*/README.org under LAYERS-DIR."
  (cl-remove-if-not
   (lambda (f)
     (let ((parts (cfg-core/--layer-path-parts f layers-dir)))
       (and (= (length parts) 3)
            (string= (nth 2 parts) "README.org"))))
   (directory-files-recursively layers-dir "\\.org$")))

(defun cfg-core/--layer-category (file layers-dir)
  "Return the category directory name for layer README FILE under LAYERS-DIR."
  (car (cfg-core/--layer-path-parts file layers-dir)))

(defun cfg-core/--layer-name (file layers-dir)
  "Return the layer directory name for layer README FILE under LAYERS-DIR."
  (nth 1 (cfg-core/--layer-path-parts file layers-dir)))

(defun cfg-core/--read-priority-number (regexp)
  "Return the first integer matching REGEXP in the current buffer, or default."
  (if (re-search-forward regexp nil t)
      (string-to-number (match-string 1))
    cfg-core--layer-default-priority))

(defun cfg-core/--category-priority (category layers-dir)
  "Return numeric priority for CATEGORY from its PRIORITY file under LAYERS-DIR."
  (let ((pri-file (expand-file-name "PRIORITY"
                                    (expand-file-name category layers-dir))))
    (if (not (file-readable-p pri-file))
        cfg-core--layer-default-priority
      (with-temp-buffer
        (insert-file-contents pri-file)
        (cfg-core/--read-priority-number "^[ \t]*\\(-?[0-9]+\\)")))))

(defun cfg-core/--layer-priority (file)
  "Return numeric #+LAYER_PRIORITY from FILE, or the default."
  (with-temp-buffer
    (insert-file-contents file nil nil 4096)
    (cfg-core/--read-priority-number
     "^#\\+LAYER_PRIORITY:[ \t]*\\(-?[0-9]+\\)")))

(defun cfg-core/--sort-layer-files (files layers-dir)
  "Return FILES sorted by category priority, layer priority, then path.
LAYERS-DIR is the directory for the layers."
  (let ((category-priority-cache (make-hash-table :test #'equal)))
    (cl-labels ((cached-category-priority (category)
                  (or (gethash category category-priority-cache)
                      (puthash category
                               (cfg-core/--category-priority category layers-dir)
                               category-priority-cache))))
      (sort (copy-sequence files)
            (lambda (a b)
              (let* ((ca (cfg-core/--layer-category a layers-dir))
                     (cb (cfg-core/--layer-category b layers-dir))
                     (cpa (cached-category-priority ca))
                     (cpb (cached-category-priority cb))
                     (lpa (cfg-core/--layer-priority a))
                     (lpb (cfg-core/--layer-priority b)))
                (cond ((/= cpa cpb) (< cpa cpb))
                      ((/= lpa lpb) (< lpa lpb))
                      (t (string< a b)))))))))

;;; Layer discovery -- manifest text / write

(defun cfg-core/--category-index-heading (category)
  "Return an Index bullet heading for CATEGORY."
  (if (<= (length category) 3)
      (format "- %s" (upcase category))
    (format "- %s" (capitalize category))))

(defun cfg-core/--layer-index-lines (files layers-dir)
  "Build Index section lines for sorted FILES under LAYERS-DIR."
  (let (lines current-cat)
    (dolist (f files)
      (let ((cat (cfg-core/--layer-category f layers-dir))
            (name (cfg-core/--layer-name f layers-dir))
            (rel (file-relative-name f layers-dir)))
        (unless (equal cat current-cat)
          (setq current-cat cat)
          (push (cfg-core/--category-index-heading cat) lines))
        (push (format "  - [[file:%s][%s]]" rel name) lines)))
    (nreverse lines)))

(defun cfg-core/--layer-include-lines (files layers-dir)
  "Build #+INCLUDE lines for sorted FILES under LAYERS-DIR."
  (mapcar (lambda (f)
            (format "#+INCLUDE: \"%s\""
                    (file-relative-name f layers-dir)))
          files))

(defun cfg-core/--layers-manifest-content (files layers-dir)
  "Return full layers/README.org text for sorted FILES under LAYERS-DIR."
  (let ((index-lines (cfg-core/--layer-index-lines files layers-dir))
        (include-lines (cfg-core/--layer-include-lines files layers-dir)))
    (concat "#+TITLE: Emacs Configuration Layers\n"
            "# Auto-generated by cfg-core/discover-layers -- do not edit by hand\n"
            "\n"
            "* Index\n"
            (if index-lines
                (concat (mapconcat #'identity index-lines "\n") "\n")
              "")
            "\n"
            "* Includes :noexport:\n"
            (mapconcat #'identity include-lines "\n")
            (if include-lines "\n" ""))))

(defun cfg-core/--file-contents (file)
  "Return contents of FILE, or nil if unreadable."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(defun cfg-core/--write-layers-manifest (manifest content)
  "Write CONTENT to MANIFEST when it differs from disk, then revert visitors."
  (unless (equal content (cfg-core/--file-contents manifest))
    (with-temp-file manifest
      (insert content)))
  ;; Always sync a visiting buffer so a stale copy cannot overwrite later.
  (when-let ((buf (get-file-buffer manifest)))
    (with-current-buffer buf
      (revert-buffer t t t)))
  manifest)

(defun cfg-core/discover-layers ()
  "Scan layers/**/README.org and rewrite layers/README.org.
Orders by category PRIORITY, then #+LAYER_PRIORITY, then path.
Reverts a visiting manifest buffer after updating."
  (let* ((layers-dir (cfg-core/--layers-dir))
         (manifest (cfg-core/--layers-manifest))
         (files (cfg-core/--sort-layer-files
                 (cfg-core/--layer-readme-files layers-dir)
                 layers-dir)))
    (cfg-core/--write-layers-manifest
     manifest
     (cfg-core/--layers-manifest-content files layers-dir))))

;;; Retangle -- expand / tangle / compile

(defun cfg-core/--load-org-element-from-source ()
  "Load the library org-element from the source code.
Work around a distro-packaged Org bug that breaks
`org-element-with-disabled-cache'.
On at least Emacs 30.2 / Org 9.7.11 (Ubuntu's emacs-common package),
org-element.elc was byte-compiled without org-macs.el loaded, so the
`org-element-with-disabled-cache' macro (defined in org-macs.el) never got
macroexpanded there and was left in the bytecode as a literal call to a
nonexistent function. That makes any org-element cache access -- and
therefore `org-export-expand-include-keyword', which our tangle pipeline
depends on -- fail with \"Invalid function: org-element-with-disabled-cache\".

Loading org-element's Lisp SOURCE instead of its .elc redefines every
function in the file, correctly macroexpanding against the org-macs already
in memory. This is safe to call even if org-element is already loaded (it
simply redefines it) and is a no-op if no source file can be found."
  (require 'org-macs)
  (let* ((compiled (locate-library "org-element"))
         (dir (and compiled (file-name-directory compiled)))
         (source (and dir
                      (or (let ((f (expand-file-name "org-element.el" dir)))
                            (and (file-exists-p f) f))
                          (let ((f (expand-file-name "org-element.el.gz" dir)))
                            (and (file-exists-p f) f))))))
    (when source
      (load source nil t))))

(defun cfg-core/--require-retangle-deps ()
  "Load Org libraries needed for include expansion and tangle."
  (cfg-core/--load-org-element-from-source)
  (require 'org)
  (require 'ox)
  (require 'ob-tangle))

(defun cfg-core/--reset-org-buffer-state ()
  "Refresh Org regexps and element cache in the current buffer."
  (org-set-regexps-and-options)
  (when (fboundp 'org-element-cache-reset)
    (org-element-cache-reset)))

(defun cfg-core/--expand-includes ()
  "Expand #+INCLUDE keywords in the current Org buffer, refreshing state."
  (cfg-core/--reset-org-buffer-state)
  (org-export-expand-include-keyword)
  (cfg-core/--reset-org-buffer-state))

(defun cfg-core/--tangle-as-init-org (init-org)
  "Tangle the current buffer as if it were INIT-ORG.
Forces `:tangle yes' targets to resolve against INIT-ORG (-> init.el) even
though variable `buffer-file-name' is a work path."
  (let ((orig (symbol-function 'org-babel-effective-tangled-filename)))
    (cl-letf (((symbol-function 'org-babel-effective-tangled-filename)
               (lambda (_buffer-fn src-lang src-tfile)
                 (funcall orig init-org src-lang src-tfile))))
      (org-babel-tangle))))

(defun cfg-core/--expand-and-tangle (dir init-org work-org)
  "In a temp buffer: load INIT-ORG from disk, expand includes, tangle.
WORK-ORG is bound as variable `buffer-file-name' so
`org-babel-map-src-blocks' does not `find-file' a live/narrowed init.org.
DIR is variable `default-directory'."
  (let ((org-confirm-babel-evaluate nil)
        (org-babel-pre-tangle-hook nil))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (setq default-directory dir)
      (insert-file-contents init-org)
      (let ((buffer-file-name work-org)
            (buffer-file-truename work-org)
            (kill-buffer-query-functions nil)
            (buffer-offer-save nil))
        (cfg-core/--expand-includes)
        ;; work-org has no live visitor except this buffer → tangle expanded content.
        (cfg-core/--tangle-as-init-org init-org)
        (set-buffer-modified-p nil)
        ;; Un-visit before kill so nothing can write work/init.org.
        (setq buffer-file-name nil
              buffer-file-truename nil)))
    (when (file-exists-p work-org)
      (delete-file work-org))))

(defun cfg-core/--delete-stale-eln (el-file)
  "Delete EL-FILE's companion .eln in the same directory, if present."
  (let ((eln (concat (file-name-sans-extension el-file) ".eln")))
    (when (file-exists-p eln)
      (delete-file eln)
      (message "Deleted stale eln: %s" eln))))

(defun cfg-core/--maybe-native-compile (init-el)
  "Native-compile INIT-EL when gcc and native-comp are available.
Only runs in interactive sessions. Batch mode (-Q) is skipped because
native-comp loads init.el to compile it and the packages it requires
are not available in a -Q environment."
  (when (and (not noninteractive)
             (file-exists-p init-el)
             (executable-find "gcc")
             (fboundp 'native-compile))
    (run-with-idle-timer 2 nil #'native-compile-async init-el)))

(defun cfg-core/retangle-init (&optional compile)
  "Retangle init.org (expanding layer includes) into Emacs Lisp / setup files.

With prefix argument COMPILE, also native compile init.el (sync in batch,
idle-async in an interactive session).

Always reads init.org from disk (same as batch CLI). Expansion + tangle run
in a throwaway buffer that never visits init.org."
  (interactive "P")
  (when cfg-core--retangling
    (user-error "Retangle already in progress"))
  (let* ((cfg-core--retangling t)
         (dir (cfg-core/--emacs-dir))
         (init-org (cfg-core/--init-org))
         (work-org (cfg-core/--retangle-work-org)))
    (unless (file-readable-p init-org)
      (user-error "Cannot read %s" init-org))
    (cfg-core/--require-retangle-deps)
    (cfg-core/discover-layers)
    (cfg-core/--expand-and-tangle dir init-org work-org)
    (let ((init-el (expand-file-name "init.el" dir)))
      (cfg-core/--delete-stale-eln init-el)
      (when compile
        (cfg-core/--maybe-native-compile init-el))
      (message "Retangled %s -> init.el, early-init.el, setup.sh" init-org)
      init-el)))

;;; After-save hook

(defun cfg-core/--retangle-source-p (file)
  "Return non-nil if FILE feeds the init.org tangle.
Matches init.org, setup-script.org, layer README.org files (not
layers/README.org), and category PRIORITY files."
  (let* ((init-org (cfg-core/--init-org))
         (setup-script-org (cfg-core/--setup-script-org))
         (layers-dir (cfg-core/--layers-dir))
         (manifest (cfg-core/--layers-manifest))
         (name (file-name-nondirectory file)))
    (or (file-equal-p file init-org)
        (file-equal-p file setup-script-org)
        (and (file-in-directory-p file layers-dir)
             (not (file-equal-p file manifest))
             (or (string= name "PRIORITY")
                 (string= name "README.org"))))))

(defun cfg-core/tangle-and-compile-init ()
  "After-save hook: retangle when saving init.org or a layer source."
  (unless cfg-core--retangling
    (when-let ((file (buffer-file-name)))
      (when (cfg-core/--retangle-source-p file)
        (cfg-core/retangle-init t)))))

(provide 'retangle)
;;; retangle.el ends here
