;;; labels.el --- Buffer labelling -*- lexical-binding: t -*-

;; Copyright (C) 2026 Daniel Russo

;; Author: Daniel Russo
;; URL: https://github.com/drusso/labels
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `labels' is a utility for labelling buffers. Labels can be used to, for
;; example, select and categorize buffers.
;;
;; For managing buffer labels, see:
;;
;; - `labels-set'
;; - `labels-add'
;; - `labels-remove'
;; - `labels-clear'
;; - `labels-clear-all'
;; - `labels-kill-buffer'
;; - `labels-kill-buffers'
;;
;; For switching buffers, see:
;;
;; - `labels-switch-to-buffer'
;; - `labels-pop-to-buffer'
;; - `labels-go-to-buffer'
;;
;; Labels can be automatically applied to buffers with the user supplied
;; `labels-label-functions'. Note that automatic labelling is available only
;; when `labels-mode' is active.
;;
;; An `ibuffer' integration is provided, see `labels-ibuffer'.

;;; Code:

(require 'cl-lib)

;;; Configuration

(defgroup labels nil
  "Buffer labels."
  :group 'convenience
  :prefix "labels-")

(defcustom labels-buffers t
  "Condition determining which buffers are candidates for labelling.

Passed as the CONDITION argument to `buffer-match-p'."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type '(buffer-predicate :label "Buffer label predicate"))

(defcustom labels-label-functions nil
  "Function, or list of functions, that specify labels for a buffer.

The function(s) is called with the buffer as temporarily current. It is
called with no arguments, and should return nil (no labels), a
label (string), or a list of labels. The returned labels are added to
the buffer.

This function(s) runs automatically when `labels-mode' is enabled, and
otherwise may be manually triggered with
`labels-add-from-label-functions' and
`labels-add-from-label-functions-all'."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type
  '(choice
    (const :label "No labelling function" nil)
    (function :label "Labelling function")
    (repeat :label "Labelling functions" function)))

(defcustom labels-delimiter "/"
  "Delimiter for nested labels.

When set to a non-nil string, labels can be nested using this delimiter.
For example, with delimiter \"/\", a label \"a/b\" is nested under \"a\".

When nil, nesting is disabled and labels are treated as flat strings."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type '(choice
          (const :label "No nesting" nil)
          (string :label "Delimiter string")))

(defcustom labels-update-functions nil
  "Hook to run when a buffer's labels are updated.

Each function is called with three arguments: the buffer whose labels
were updated, the current list of labels, and the previous list of
labels."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type 'hook)

(defcustom labels-go-to-display-function
  #'labels--display-buffer-prefer-same-window
  "Display function used by `labels-go-to-buffer'.

The function should accept a buffer as its argument and display it."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type 'function)

(defcustom labels-mode-line-format #'labels--mode-line-labels
  "Function returning the mode line construct used by `labels-mode'.

The construct is shown as the mode's lighter."
  :group 'labels
  :package-version '(labels . "0.1.0")
  :type 'function)

;;; Faces

(defgroup labels-faces nil
  "Faces used by `labels'."
  :group 'labels
  :group 'faces)

(defface labels-mode-line '((t :inherit mode-line-emphasis))
  "Face used for displaying labels in the mode line."
  :group 'labels-faces
  :package-version '(labels . "0.1.0"))

(defface labels-buffer-name '((t :inherit font-lock-function-name-face))
  "Face used for displaying buffer names."
  :group 'labels-faces
  :package-version '(labels . "0.1.0"))

(defface labels-buffer-count '((t :inherit font-lock-constant-face
                                  :slant italic))
  "Face used for displaying buffer counts."
  :group 'labels-faces
  :package-version '(labels . "0.1.0"))

(defface labels-label '((t :inherit font-lock-keyword-face))
  "Face used for displaying labels."
  :group 'labels-faces
  :package-version '(labels . "0.1.0"))

(defface labels-key-binding '((t :inherit help-key-binding))
  "Face used for displaying key bindings."
  :group 'labels-faces
  :package-version '(labels . "0.1.0"))

;;; Labelling Internals

(defvar-local labels--buffer-labels nil
  "List of labels for the current buffer.")

(put 'labels--buffer-labels 'permanent-local t)

(defun labels--get-labels (buffer &optional prefixes)
  "Get the list of labels for BUFFER.

If PREFIXES is non-nil, each label is expanded into all of its prefixes,
per `labels-delimiter'. For example, a label \"a/b/c\" would be returned
as (\"a\" \"a/b\" \"a/b/c\")."
  (let ((labels
         (buffer-local-value 'labels--buffer-labels buffer)))
    (if prefixes
        (mapcan #'labels--label-prefixes labels)
      labels)))

(defun labels--is-member (label labels &optional parent)
  "Check if LABEL is in LABELS.

If PARENT is non-nil, checks if LABEL is a parent of any of LABELS. This
applies only when `labels-delimiter' is non-nil."
  (if parent
      (let ((label-parts (labels--split-label label)))
        (cl-some
         #'(lambda (candidate)
             (let ((candidate-parts (labels--split-label candidate)))
               (equal label-parts
                      (seq-take candidate-parts (length label-parts)))))
         labels))
    (member label labels)))

(defun labels--has-label (buffer label &optional parent)
  "Check if BUFFER is labelled with LABEL.

If PARENT is non-nil, checks if LABEL is a parent of any of the buffer's
labels. This applies only when `labels-delimiter' is non-nil."
  (labels--is-member label (labels--get-labels buffer) parent))

(defun labels--has-labels (buffer labels &optional parents)
  "Check if BUFFER is labelled with all LABELS.

If PARENTS is non-nil, each LABEL may be a parent of any of the buffer's
labels."
  (let ((buffer-labels (labels--get-labels buffer)))
    (cl-every
     (lambda (label)
       (labels--is-member label buffer-labels parents))
     labels)))

(defun labels--buffers-with-labels (labels &optional parents)
  "Return a list of buffers that have all LABELS.

If PARENTS is non-nil, each of LABELS may be a parent of a buffer's
label.

Returns nil if LABELS is empty."
  (when labels
    (cl-remove-if-not
     (lambda (buffer)
       (labels--has-labels buffer labels parents))
     (labels--buffer-list-labelled))))

(defun labels--split-label (label)
  "Split LABEL into its parts, per `labels-delimiter'."
  (if labels-delimiter
      (split-string label (regexp-quote labels-delimiter))
    (list label)))

(defun labels--label-prefixes (label)
  "Return all prefixes of LABEL split by `labels-delimiter'.

For example, given a delimiter of \"/\":

- an input of \"a/b/c\" returns (\"a\" \"a/b\" \"a/b/c\")
- an input of \"a//b\" returns (\"a\" \"a/\" \"a//b\")
- an input of \"/a\" returns (\"\" \"/a\")"
  (let ((parts (labels--split-label label)))
    (mapcar (lambda (count)
              (string-join (seq-take parts count) labels-delimiter))
            (number-sequence 1 (length parts)))))

(defun labels--validate-buffer (buffer)
  "Signal a `user-error' if BUFFER cannot be labelled."
  (unless (labels-buffer-p buffer)
    (user-error "%s cannot be labelled, see %s"
                (labels--format-buffers buffer)
                (labels--format-command 'labels-buffer-p))))

(defun labels--validate-selection (labels)
  "Signal a `user-error' if LABELS is empty, otherwise return LABELS."
  (unless labels
    (user-error "No labels selected"))
  labels)

(defun labels--buffer-list ()
  "Get the buffers that are candidates for labelling.

Candidate buffers are determined by `labels-buffer-p'."
  (cl-remove-if-not #'labels-buffer-p (buffer-list)))

(defun labels--buffer-list-labelled ()
  "Get the buffers that have at least one label."
  (cl-remove-if-not
   #'(lambda (buffer)
       (labels--get-labels buffer))
   (labels--buffer-list)))

(defun labels--all-labels (&optional parents)
  "Return a list of all labels across all buffers.

If PARENTS is non-nil, include the parents of each label."
  ;; With PARENTS, labels starting with the delimiter yield an empty prefix
  ;; (ex. "/a" yields "" and "/a"). `completing-read-multiple' discards empty
  ;; entries, so the empty prefix could never be selected.
  (remove ""
          (cl-remove-duplicates
           (apply #'append
                  (mapcar (lambda (buffer)
                            (labels--get-labels buffer parents))
                          (labels--buffer-list)))
           :test #'equal)))

(defun labels--label-valid-p (label)
  "Check if LABEL is valid.

All non-empty strings are valid."
  (and (stringp label)
       (not (string-blank-p label))))

(defun labels--unique (labels)
  "Return LABELS with duplicates removed."
  (cl-remove-duplicates labels :test #'equal))

(define-error 'labels-invalid-label "Invalid label")

(defun labels--require-valid-labels (labels)
  "Deduplicate LABELS and return them.

Signal `labels-invalid-label' if any is invalid."
  (let* ((unique-labels (labels--unique labels))
         (invalid-labels (cl-remove-if #'labels--label-valid-p
                                       unique-labels)))
    (when invalid-labels
      (signal 'labels-invalid-label invalid-labels))
    unique-labels))

(defun labels--require-valid-input (labels)
  "Like `labels--require-valid-labels', but signal a
`user-error' to flag invalid user input."
  (condition-case err
      (labels--require-valid-labels labels)
    (labels-invalid-label
     (user-error "%s" (error-message-string err)))))

(defun labels--validate-labels (labels)
  "Deduplicate LABELS and return only those that are valid."
  (let* ((unique-labels (labels--unique labels))
         (valid-labels (cl-remove-if-not #'labels--label-valid-p
                                         unique-labels))
         (invalid-labels (cl-remove-if #'labels--label-valid-p
                                       unique-labels)))
    (cond
     ((> (length invalid-labels) 1)
      (message "Invalid labels, ignoring: %S" invalid-labels))
     ((= (length invalid-labels) 1)
      (message "Invalid label, ignoring: %S" (car invalid-labels))))
    valid-labels))

(defun labels--set-labels (buffer labels)
  "Set LABELS for BUFFER.

Return non-nil if BUFFER's labels changed."
  (let* ((valid-labels (labels--validate-labels labels))
         (old-labels (labels--get-labels buffer)))
    (unless (equal (sort old-labels :lessp #'labels--label-less-p)
                   (sort valid-labels :lessp #'labels--label-less-p))
      (with-current-buffer buffer
        (setq labels--buffer-labels (copy-sequence valid-labels))
        (force-mode-line-update))
      (run-hook-with-args 'labels-update-functions
                          buffer valid-labels old-labels)
      t)))

(defun labels--add-labels (buffer labels)
  "Add multiple LABELS to BUFFER.

Return non-nil if BUFFER's labels changed."
  (labels--set-labels buffer
                      (seq-union (labels--get-labels buffer) labels)))

(defun labels--remove-labels (buffer labels)
  "Remove multiple LABELS from BUFFER.

Return non-nil if BUFFER's labels changed."
  (let ((labels-next (labels--get-labels buffer)))
    (dolist (label labels)
      (setq labels-next (remove label labels-next)))
    (labels--set-labels buffer labels-next)))

(defun labels--remove-label (buffer label)
  "Remove LABEL from BUFFER."
  (labels--remove-labels buffer (list label)))

(defun labels--get-labels-union (buffers)
  "Get the labels from all BUFFERS."
  (let ((buffers (seq-filter #'labels-buffer-p buffers)))
    (cl-remove-duplicates
     (apply #'append (mapcar #'labels--get-labels buffers))
     :test #'equal)))

(defun labels--get-labels-intersection (buffers)
  "Get the labels common to all BUFFERS."
  (when-let* ((buffers (seq-filter #'labels-buffer-p buffers)))
    (let ((first-labels (labels--get-labels (car buffers))))
      (cl-remove-if-not
       (lambda (label)
         (cl-every
          (lambda (buffer) (labels--has-label buffer label))
          (cdr buffers)))
       first-labels))))

;;; Sorting

(defun labels--label-less-p (a b)
  "Predicate function used as the sort comparator for ordering labels.

This function is passed as the LESSP argument to `sort'. Returns non-nil
if the first label (A) should sort before the second label (B)."
  (value< (labels--split-label a) (labels--split-label b)))

(defun labels--labels-less-p (a b)
  "Return non-nil if the list of labels A sorts before list B.

This function may be used as the LESSP argument to `sort'."
  (value< (sort a :lessp #'labels--label-less-p)
          (sort b :lessp #'labels--label-less-p)))

;;; Formatting

(defun labels--format-labels (labels)
  "Return LABELS as a sorted, comma-separated string for display."
  (string-join
   (mapcar (lambda (label) (propertize label 'face 'labels-label))
           (sort labels :lessp #'labels--label-less-p))
   ", "))

(defun labels--format-buffers (buffer)
  "Return BUFFER for display: a buffer, or a list of buffers.

A list of more than one buffer, or none, is shown as a count."
  (cond
   ((null buffer)
    (propertize "0 buffers" 'face 'labels-buffer-count))
   ((bufferp buffer)
    (propertize (buffer-name buffer) 'face 'labels-buffer-name))
   ((= (length buffer) 1)
    (propertize (buffer-name (car buffer)) 'face 'labels-buffer-name))
   ((> (length buffer) 1)
    (propertize (format "%d buffers" (length buffer))
                'face 'labels-buffer-count))
   (t
    nil)))

(defun labels--format-buffer (buffer)
  "Return the name of BUFFER for display."
  (propertize (buffer-name buffer) 'face 'labels-buffer-name))

(defun labels--format-command (command)
  "Format COMMAND for display."
  (propertize (symbol-name command) 'face 'labels-key-binding))

;;; Reading

(defvar labels-history nil
  "Minibuffer history of labels.")

(defun labels--label-annotation (label parent)
  "Return the completion annotation for LABEL.

If PARENT is non-nil, count buffers with labels under LABEL too."
  (let* ((buffers (labels--buffers-with-labels (list label) parent))
         (count (length buffers))
         (noun (if (= count 1) "buffer" "buffers"))
         (count-label (propertize (format " %d %s" count noun)
                                  'face 'completions-annotations))
         (buffer-names (mapcar #'labels--format-buffer buffers))
         (buffer-list (if buffer-names
                          (format " %s" (string-join buffer-names ", "))
                        "")))
    (concat
     (propertize " " 'display '(space :align-to 25))
     count-label
     buffer-list)))

(cl-defun labels--read-labels
    (prompt &key (require-match t) initial-labels predicate parents)
  "Read multiple labels from the user with PROMPT.

When REQUIRE-MATCH is nil, allow creating new labels.

The input is initially populated with INITIAL-LABELS.

PREDICATE is a function takes a label (a string) and returns non-nil if
the label should be included in the completion list.

If PARENTS is non-nil, also offer the parents of labels."
  (let* ((all-labels (labels--all-labels parents))
         (filtered-labels
          (if predicate (cl-remove-if-not predicate all-labels)
           all-labels))
         (initial-input
          (when initial-labels
           (concat (labels--format-labels initial-labels) ","))))
    (cond
     ((and
       (null filtered-labels) require-match)
      (user-error "No labels"))
     (t
      (labels--require-valid-input
      (let ((completion-extra-properties
             (list :category 'labels
                   :annotation-function
                   (lambda (label)
                     (labels--label-annotation label parents)))))
        (completing-read-multiple
         prompt
         filtered-labels
         predicate
         require-match
         initial-input
         'labels-history)))))))

(defun labels--read-buffer (verb labels buffers)
  "Prompt for a buffer from BUFFERS.

VERB and LABELS are used to construct the prompt."
  (get-buffer (read-buffer (format "%s buffer labelled %s: "
                                   verb
                                   (labels--format-labels labels))
                           nil ; default
                           t ; require-match
                           (lambda (b)
                             (member (get-buffer (if (consp b) (car b) b))
                                     buffers)))))

(defun labels--read-labels-to-set (buffers)
  "Prompt the user for labels to be set on each buffer in BUFFERS."
  (labels--read-labels
   (format "Set labels on %s: " (labels--format-buffers buffers))
   :require-match nil
   :initial-labels
   (when (length= buffers 1)
     (labels--get-labels (car buffers)))))

(defun labels--read-labels-to-add (buffers)
  "Prompt the user for labels to be added to each buffer in BUFFERS."
  (let ((labels (labels--get-labels-intersection buffers)))
    (labels--read-labels
     (format "Add labels to %s: " (labels--format-buffers buffers))
     :require-match nil
     :predicate
     (lambda (label)
       (not (labels--is-member label labels))))))

(defun labels--read-labels-to-remove (buffers)
  "Prompt the user for labels to be removed from each buffer in BUFFERS."
  (let ((labels (labels--get-labels-union buffers)))
    (labels--read-labels
     (format "Remove labels from %s: " (labels--format-buffers buffers))
     :predicate
     (lambda (label)
       (labels--is-member label labels)))))

;;; Labelling

(defun labels--buffer-baseline-p (buffer)
  "Return non-nil if BUFFER is live and not internal.

This is the part of `labels-buffer-p' that does not depend on
`labels-buffers'."
  (and
   (buffer-live-p buffer)
   ;; Exclude internal buffers (buffers that start with a space).
   (not (string-prefix-p " " (buffer-name buffer)))))

(defun labels-buffer-p (buffer)
  "Return non-nil if BUFFER is a candidate for labelling.

Non-live and internal buffers (buffers with names that start with a
space) cannot be labelled.

See `labels-buffers' for additional conditions the user may configure."
  (and
   (labels--buffer-baseline-p buffer)
   (with-demoted-errors
       "Error evaluating `labels-buffers' condition with `buffer-match-p': %S"
     (buffer-match-p labels-buffers buffer))))

(cl-defun labels-labelled-p (label &key buffer parents)
  "Return non-nil if BUFFER is labelled with LABEL.

BUFFER is a buffer or buffer name, and defaults to the current buffer.

If PARENTS is non-nil, LABEL may also be a parent of BUFFER's labels.
For example, \"a\" matches a buffer labelled \"a/b\"."
  (labels--has-label (window-normalize-buffer buffer) label parents))

(cl-defun labels-get-labelled (label &key parents)
  "Return the buffers labelled with LABEL.

If PARENTS is non-nil, LABEL may also be a parent of a buffer's labels.
For example, \"a\" matches a buffer labelled \"a/b\"."
  (cl-remove-if-not #'(lambda (buffer)
                        (labels--has-label buffer label parents))
                    (labels--buffer-list)))

(defun labels--add-fn-labels (&optional buffer)
  "Add labels returned by `labels-label-functions' to the current buffer.

If BUFFER is non-nil, labels BUFFER instead of the current buffer."
  (when-let* ((buffer (or buffer (current-buffer)))
              labels-label-functions
              (_ (labels-buffer-p buffer))
              (fns (cond
                    ((functionp labels-label-functions)
                     (list labels-label-functions))
                    ((listp labels-label-functions) labels-label-functions)))
              (labels (with-current-buffer buffer
                      (cl-mapcan
                       (lambda (fn)
                         (with-demoted-errors
                             "Error evaluating `labels-label-functions': %S"
                           (let ((result (funcall fn)))
                             (cond
                              ((null result) nil)
                              ((stringp result) (list result))
                              ;; Copy the result, since `cl-mapcan' mutates the
                              ;; lists returned by `fn'.
                              ((proper-list-p result) (copy-sequence result))
                              (t nil)))))
                       fns))))
    (labels--add-labels buffer labels)))

;;;###autoload
(defun labels-add-from-label-functions (&optional buffer)
  "Add labels returned by `labels-label-functions' to the current buffer.

If BUFFER is non-nil, labels BUFFER instead of the current buffer."
  (interactive)
  (labels--add-fn-labels (window-normalize-buffer buffer)))

;;;###autoload
(defun labels-add-from-label-functions-all ()
  "Add labels returned by `labels-label-functions' to all candidate buffers.

Candidate buffers are determined by `labels-buffer-p'."
  (interactive)
  (dolist (buffer (labels--buffer-list))
    (labels--add-fn-labels buffer)))

;;;###autoload
(defun labels-set (labels &optional buffer)
  "Label BUFFER with LABELS, replacing all existing labels.

Uses the current buffer when called interactively or if BUFFER is nil."
  (interactive
   (let ((buffer (current-buffer)))
        (labels--validate-buffer buffer)
        (list (labels--read-labels-to-set (list buffer)) buffer)))
  (let* ((buffer (window-normalize-buffer buffer))
         (labels (labels--require-valid-labels labels)))
    (labels--validate-buffer buffer)
    (labels--set-labels buffer labels)
    (message "Set label%s %s on buffer %s"
             (if (= (length labels) 1) "" "s")
             (labels--format-labels labels)
             (labels--format-buffers buffer))
    nil))

;;;###autoload
(defun labels-add (labels &optional buffer)
  "Add LABELS to BUFFER without removing existing labels.

BUFFER is a buffer or buffer name, and defaults to the current buffer."
  (interactive
   (let ((buffer (current-buffer)))
    (labels--validate-buffer buffer)
    (list (labels--read-labels-to-add (list buffer)) buffer)))
  (let* ((buffer (window-normalize-buffer buffer))
         (labels (labels--require-valid-labels labels)))
    (labels--validate-buffer buffer)
    (labels--add-labels buffer labels)
    (message "Added label%s %s to buffer %s"
             (if (= (length labels) 1) "" "s")
             (labels--format-labels labels)
             (labels--format-buffers buffer))
    nil))

;;;###autoload
(defun labels-remove (labels &optional buffer)
  "Remove LABELS from BUFFER.

BUFFER is a buffer or buffer name, and defaults to the current buffer."
  (interactive
   (let ((buffer (current-buffer)))
     (labels--validate-buffer buffer)
     (unless (labels--get-labels buffer)
       (user-error "No labels on %s" (labels--format-buffers buffer)))
     (list (labels--read-labels-to-remove (list buffer)) buffer)))
  (let* ((buffer (window-normalize-buffer buffer)))
    (labels--validate-buffer buffer)
    (labels--remove-labels buffer labels)
    (message "Removed label%s %s from buffer %s"
             (if (= (length labels) 1) "" "s")
             (labels--format-labels labels)
             (labels--format-buffers buffer))
    nil))

;;;###autoload
(defun labels-clear (&optional buffer)
  "Remove all labels from BUFFER.

BUFFER is a buffer or buffer name, and defaults to the current buffer."
  (interactive
   (let ((buffer (current-buffer)))
     (labels--validate-buffer buffer)
     (list buffer)))
  (let ((buffer (window-normalize-buffer buffer)))
    (labels--validate-buffer buffer)
    (let ((labels (labels--get-labels buffer)))
      (cond
       ((null labels)
        (message "No labels on %s" (labels--format-buffers buffer)))
       (t
        (labels--remove-labels buffer labels)
        (message "Removed all labels %s from %s"
                 (labels--format-labels labels)
                 (labels--format-buffers buffer))))
      nil)))

;;;###autoload
(defun labels-clear-all ()
  "Clear all labels from all buffers."
  (interactive)
  (let ((labelled-buffers (labels--buffer-list-labelled)))
    (cond
     ((null labelled-buffers)
      (message "No labelled buffers"))
     ((y-or-n-p (format "Clear all labels from %s? "
                        (labels--format-buffers labelled-buffers)))
      (dolist (buffer labelled-buffers)
        (labels--set-labels buffer nil))
      (message "Cleared labels from %s"
               (labels--format-buffers labelled-buffers))))
    nil))

;;;###autoload
(defun labels-kill-buffer (labels)
  "Kill a buffer with LABELS.

If only one buffer has LABELS, kill it without prompting."
  (interactive
   (list (labels--read-labels "Kill buffer with labels: ")))
  (labels--validate-selection labels)
  (let* ((buffers (labels--buffers-with-labels labels))
         (sole (null (cdr buffers)))
         (labels-label (labels--format-labels labels)))
    (if (null buffers)
        (message "No buffers labelled %s" labels-label)
      (let* ((buffer (if sole
                         (car buffers)
                       (labels--read-buffer "Kill" labels buffers)))
             ;; A killed buffer has no name, so do the formatting first.
             (msg (format "Killed %s%s labelled %s"
                          (if sole "sole buffer " "")
                          (labels--format-buffer buffer)
                          labels-label)))
        (when (kill-buffer buffer)
          (message "%s" msg))))
    nil))

;;;###autoload
(defun labels-kill-buffers (labels)
  "Kill all buffers with LABELS."
  (interactive
   (list (labels--read-labels "Kill buffers with labels: ")))
  (labels--validate-selection labels)
  (let* ((buffers (labels--buffers-with-labels labels))
         (count (length buffers))
         (buffers-label (if (= count 1) "buffer" "buffers"))
         (labels-label (labels--format-labels labels)))
    (cond
     ((zerop count)
      (message "No buffers labelled %s" labels-label))
     ((y-or-n-p (format "Kill %d %s labelled %s? "
                        count buffers-label labels-label))
      (mapc #'kill-buffer buffers)
      ;; A kill may be refused (for example, when a buffer is modified), or one
      ;; kill results in additional kills (for example, as with indirect
      ;; buffers). So we count by liveliness.
      (message "Killed %d of %d %s labelled %s"
               (cl-count-if-not #'buffer-live-p buffers)
               count buffers-label labels-label))
     (t
      (message "Aborted killing buffers labelled %s" labels-label)))
    nil))

;;; Switching

(defun labels--display-buffer-prefer-same-window (buffer)
  "Display BUFFER, preferring the same window if BUFFER isn't already visible.
If BUFFER is already displayed in a window, reuse that window and select
it."
  (when-let* ((window
               (display-buffer buffer
                               '((display-buffer-reuse-window
                                  display-buffer-same-window)
                                 (inhibit-same-window . nil)))))
    (select-window window)))

(defun labels--do-switch (display-fn labels parents)
  "Display a buffer with all LABELS using DISPLAY-FN.

If PARENTS is non-nil, LABELS may be parents of a buffer's labels.
Select the sole matching buffer directly, otherwise prompt."
  (let* ((buffers (labels--buffers-with-labels labels parents))
         (labels-label (labels--format-labels labels)))
    (cond
     ((null buffers)
      (message "No buffers labelled %s" labels-label)
      nil)
     ((= 1 (length buffers))
      (let ((selected-buffer (car buffers)))
        (funcall display-fn selected-buffer)
        (message "Switched to sole buffer %s labelled %s"
                 (labels--format-buffers selected-buffer)
                 labels-label)
        selected-buffer))
     (t
      (when-let* ((selected-buffer
                   (labels--read-buffer "Select" labels buffers)))
        (funcall display-fn selected-buffer)
        (message "Switched to buffer %s labelled %s"
                 (labels--format-buffers selected-buffer)
                 labels-label)
        selected-buffer)))))

(defun labels--handle-switching-command (display-fn display-name labels)
  "Display a buffer with LABELS using DISPLAY-FN.

If LABELS is nil, prompt for them, using DISPLAY-NAME in the prompt."
  (let ((selected-labels
         (or labels (labels--read-labels (format "%s buffer with labels: "
                                           display-name)))))
    (labels--validate-selection selected-labels)
    (labels--do-switch display-fn selected-labels nil)))

;;;###autoload
(defun labels-switch-to-buffer (&optional labels)
  "Switch to a buffer with LABELS, prompting for them if nil."
  (interactive)
  (labels--handle-switching-command #'switch-to-buffer "Switch to" labels))

;;;###autoload
(defun labels-pop-to-buffer (&optional labels)
  "Pop to a buffer with LABELS, prompting for them if nil."
  (interactive)
  (labels--handle-switching-command #'pop-to-buffer "Pop to" labels))

;;;###autoload
(defun labels-go-to-buffer (&optional labels)
  "Go to a buffer with LABELS, prompting for them if nil.

Uses `labels-go-to-display-function' for display."
  (interactive)
  (labels--handle-switching-command labels-go-to-display-function
                                    "Go to" labels))

;;; Keymap

;;;###autoload
(defvar-keymap labels-keymap
  :doc "Keymap for `labels' commands."
  "b" #'labels-switch-to-buffer
  "p" #'labels-pop-to-buffer
  "g" #'labels-go-to-buffer
  "s" #'labels-set
  "a" #'labels-add
  "c" #'labels-clear
  "r" #'labels-remove
  "k" #'labels-kill-buffer
  "K" #'labels-kill-buffers)

;;; Mode

(defvar-local labels--labels-fn-timer nil)
(put 'labels--labels-fn-timer 'permanent-local t)

(defun labels--after-change-major-mode ()
  "Schedule labelling of the current buffer by `labels-label-functions'."
  ;; Defer this call to wait until the buffer's state is fully initialized and
  ;; the buffer is part of the frame's internal 'buffer-list.
  (let ((buffer (current-buffer)))
    (when (labels--buffer-baseline-p buffer)
      (when-let* ((timer (buffer-local-value 'labels--labels-fn-timer buffer)))
        (cancel-timer timer))
      (setq-local labels--labels-fn-timer
                  (run-with-idle-timer 0 nil #'labels--add-fn-labels buffer)))))

(defun labels--mode-line-labels ()
  "Return the current buffer's labels for the mode line."
  (let ((labels (labels--get-labels (current-buffer))))
    (if labels
        (append
         (list " [")
         (cdr (mapcan (lambda (label)
                        (list ", "
                              ;; Escape %. Otherwise, for example, "%b" would
                              ;; show the buffer name.
                              (propertize (string-replace "%" "%%" label)
                                          'face 'labels-mode-line)))
                      (sort labels :lessp #'labels--label-less-p)))
         (list "]"))
      "")))

;;;###autoload
(define-minor-mode labels-mode
  "Minor mode for `labels'.

This minor mode:

- automatically adds labels to buffers, per `labels-label-functions',
- displays a buffer's labels in the mode line."
  :global t
  :lighter (:eval (funcall labels-mode-line-format))
  :group 'labels
  (if labels-mode
      (progn
        (labels-add-from-label-functions-all)
        (add-hook 'after-change-major-mode-hook
                  #'labels--after-change-major-mode))
    (remove-hook 'after-change-major-mode-hook
                 #'labels--after-change-major-mode)))

;;; Ibuffer

(declare-function labels-ibuffer-mode "labels-ibuffer")

;;;###autoload
(defun labels-ibuffer ()
  "Install `labels' `ibuffer' integration.

Adds a column, sorter, filter, and ops (set, add, and remove).

Note that to view the column, `ibuffer-formats' must include a format
with the `labels' column."
  (require 'labels-ibuffer)
  (add-hook 'ibuffer-mode-hook #'labels-ibuffer-mode))

;;; Fin

(provide 'labels)

;;; labels.el ends here
