;;; labels-ibuffer.el --- Ibuffer support for labels -*- lexical-binding: t -*-

;; Copyright (C) 2026 Daniel Russo

;; Author: Daniel Russo
;; URL: https://github.com/drusso/labels

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

;; `ibuffer' column, sorter, filter, mark command, and ops for `labels'.
;; Enable with `labels-ibuffer'.

;;; Code:

(require 'cl-lib)
(require 'ibuffer)
(require 'ibuf-ext)
(require 'labels)

(defvar labels-ibuffer--skipped 0
  "Number of buffers the current ibuffer op skipped.")

(defvar labels-ibuffer--unchanged 0
  "Number of buffers the current ibuffer op left unchanged.")

(defun labels-ibuffer--reset ()
  "Reset the counts of the current ibuffer op."
  (setq labels-ibuffer--skipped 0
        labels-ibuffer--unchanged 0))

(defun labels-ibuffer--apply (buffer fn)
  "Call FN with BUFFER if it can be labelled, otherwise skip it.

Returns t if FN changed BUFFER's labels. Otherwise, increments
`labels-ibuffer--skipped' or `labels-ibuffer--unchanged' and returns
nil."
  (cond
   ((not (labels-buffer-p buffer))
    (cl-incf labels-ibuffer--skipped)
    nil)
   ((funcall fn buffer)
    t)
   (t
    (cl-incf labels-ibuffer--unchanged)
    nil)))

(defun labels-ibuffer--opstring (opstring)
  "Return OPSTRING, preceded by the unchanged and skipped counts, if any.

Ibuffer reports \"Operation finished; OPSTRING N buffers\", for example:
\"Operation finished; 2 unchanged, 1 skipped (cannot be labelled);
removed labels from 2 buffers\"."
  (let ((counts
         (delq nil
               (list (unless (zerop labels-ibuffer--unchanged)
                       (format "%d unchanged" labels-ibuffer--unchanged))
                     (unless (zerop labels-ibuffer--skipped)
                       (format "%d skipped (cannot be labelled)"
                               labels-ibuffer--skipped))))))
    (if (null counts)
        opstring
      (format "%s; %s" (string-join counts ", ") opstring))))

(define-ibuffer-column labels
  (:name "Labels")
  (labels--format-labels (labels--get-labels buffer)))

(define-ibuffer-sorter labels
  "Sort the buffers by their labels."
  (:description "labels")
  (labels--labels-less-p
   (labels--get-labels (car a)) (labels--get-labels (car b))))

(define-ibuffer-filter labels
    "Limit current view to buffers with all labels in QUALIFIER."
  (:description "labels"
                :reader (labels--validate-selection
                         (labels--read-labels "Filter by label: " :parents t)))
  (labels--has-labels buf qualifier t))

(defun labels-ibuffer-mark-by-labels (labels)
  "Mark all buffers whose labels match LABELS."
  (interactive
   (list (labels--validate-selection
          (labels--read-labels "Mark by labels: " :parents t))))
  (ibuffer-mark-on-buffer
   (lambda (buf)
     (labels--has-labels buf labels t))))

(define-ibuffer-op set-labels (labels)
  "Set labels on marked buffers, replacing all existing labels."
  (:opstring (lambda () (labels-ibuffer--opstring "set labels on"))
   :active-opstring "Set labels on"
   :interactive (list (labels--read-labels-to-set
                       (or (ibuffer-get-marked-buffers)
                           (list (ibuffer-current-buffer t)))))
   :before (labels-ibuffer--reset)
   :complex t
   :modifier-p nil)
  (labels-ibuffer--apply buf (lambda (buffer)
                               (labels--set-labels buffer labels))))

(define-ibuffer-op add-labels (labels)
  "Add labels to marked buffers, keeping existing labels."
  (:opstring (lambda () (labels-ibuffer--opstring "added labels to"))
   :active-opstring "Add labels to"
   :interactive (list (labels--read-labels-to-add
                       (or (ibuffer-get-marked-buffers)
                           (list (ibuffer-current-buffer t)))))
   :before (labels-ibuffer--reset)
   :complex t
   :modifier-p nil)
  (when labels
    (labels-ibuffer--apply buf (lambda (buffer)
                                 (labels--add-labels buffer labels)))))

(define-ibuffer-op remove-labels (labels)
  "Remove the selected labels from marked buffers."
  (:opstring (lambda () (labels-ibuffer--opstring "removed labels from"))
   :active-opstring "Remove labels from"
   :interactive (list (labels--read-labels-to-remove
                       (or (ibuffer-get-marked-buffers)
                           (list (ibuffer-current-buffer t)))))
   :before (labels-ibuffer--reset)
   :complex t
   :modifier-p nil)
  (when labels
    (labels-ibuffer--apply buf (lambda (buffer)
                                 (labels--remove-labels buffer labels)))))

(defvar-keymap labels-ibuffer-mode-map
  :doc "Keymap for `labels-ibuffer-mode'."
  "# s" #'ibuffer-do-set-labels
  "# a" #'ibuffer-do-add-labels
  "# r" #'ibuffer-do-remove-labels
  "/ #" #'ibuffer-filter-by-labels
  "% #" #'labels-ibuffer-mark-by-labels
  "s #" #'ibuffer-do-sort-by-labels)

(define-minor-mode labels-ibuffer-mode
  "Minor mode for `labels' integration with `ibuffer'."
  :lighter nil
  :keymap labels-ibuffer-mode-map
  :group 'labels)

(provide 'labels-ibuffer)

;;; labels-ibuffer.el ends here
