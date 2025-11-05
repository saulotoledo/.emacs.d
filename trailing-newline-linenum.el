;;; trailing-newline-linenum.el --- Show line number for trailing newline in fringe/margin -*- lexical-binding: t; -*-
;;; Commentary:
;; trailing-newline-linenum.el provides a minor mode to display a special indicator
;; (icon and small line number) in the left margin for a trailing newline at the end of a file.
;; It is robust against most buffer changes, but overlays may be removed by some operations.
;;
;; Usage:
;;   (load-file "~/.emacs.d/trailing-newline-linenum.el")
;;   (trailing-newline-linenum-mode 1)

;;; Code:

(defvar trailing-newline-linenum--overlay nil
  "Overlay used to display the trailing newline indicator in the margin.")

;; Reserved for future use (not currently used).
(defvar trailing-newline-linenum--bitmap nil
  "Bitmap for custom fringe indicator (not currently used).")

(defun trailing-newline-linenum--update (&rest _)
  "Update the trailing newline indicator overlay in the current buffer.
Removes any existing overlay, and if the buffer ends with a newline,
adds an indicator in the left margin for the visual empty line."
  (when trailing-newline-linenum--overlay
    (delete-overlay trailing-newline-linenum--overlay)
    (setq trailing-newline-linenum--overlay nil))
  (when (and (eq (char-before (point-max)) ?\n)
             (not (eq (point-min) (point-max))))
    (save-excursion
      (goto-char (1- (point-max)))
      (let* ((ov (make-overlay (point-max) (point-max)))
             (win (get-buffer-window (current-buffer)))
             (ln-width (if (bound-and-true-p display-line-numbers)
                           (let ((w (or (and win (window-parameter win 'line-number-width))
                                        (length (number-to-string (line-number-at-pos (point-max)))))))
                             (max 2 w))
                         2))
             (line (line-number-at-pos (1- (point-max))))
             (nl-symbol (propertize "⏎" 'face 'line-number))
             (small-num (propertize (format "%d" (1+ line)) 'face 'trailing-newline-linenum-small-number)))
        ;; Ensure margin is wide enough for line numbers
        (when win
          (set-window-margins win ln-width (cdr (window-margins win))))
        (overlay-put ov 'after-string
                     (propertize "\u200b" 'display `(margin left-margin ,(concat nl-symbol " " small-num))))
        (overlay-put ov 'priority 9999)
        (setq trailing-newline-linenum--overlay ov)))))

;; Face for the small trailing newline line number.
(defface trailing-newline-linenum-small-number
  '((t :height 0.7 :inherit line-number))
  "Face for the small trailing newline line number.")

;;;###autoload
(define-minor-mode trailing-newline-linenum-mode
  "Minor mode to show a special indicator for trailing newlines.
When enabled, displays an icon and small line number in the margin
for the visual empty line created by a trailing newline at the end
of the file."
  :lighter " TNLN"
  (let ((update-fn #'trailing-newline-linenum--update))
    (if trailing-newline-linenum-mode
        (progn
          ;; Use focus-in-hook if available and not obsolete, else use after-focus-change-function (Emacs 27.1+)
          (if (boundp 'after-focus-change-function)
              (add-hook 'after-focus-change-function update-fn nil t)
            (add-hook 'focus-in-hook update-fn nil t))
          (add-hook 'after-change-functions update-fn nil t)
          (add-hook 'window-configuration-change-hook update-fn nil t)
          (add-hook 'find-file-hook update-fn nil t)
          (add-hook 'after-save-hook update-fn nil t)
          (add-hook 'after-revert-hook update-fn nil t)
          (add-hook 'post-command-hook update-fn nil t)
          (funcall update-fn))
      (if (boundp 'after-focus-change-function)
          (remove-hook 'after-focus-change-function update-fn t)
        (remove-hook 'focus-in-hook update-fn t))
      (remove-hook 'after-change-functions update-fn t)
      (remove-hook 'window-configuration-change-hook update-fn t)
      (remove-hook 'find-file-hook update-fn t)
      (remove-hook 'after-save-hook update-fn t)
      (remove-hook 'after-revert-hook update-fn t)
      (remove-hook 'post-command-hook update-fn t)
      (when trailing-newline-linenum--overlay
        (delete-overlay trailing-newline-linenum--overlay)
        (setq trailing-newline-linenum--overlay nil)))))

(provide 'trailing-newline-linenum)
;;; trailing-newline-linenum.el ends here
