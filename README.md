# Labels

Labels is an Emacs utility for labelling buffers. Labels can be used to, for
example, select and categorize buffers.

## Installation

Requires Emacs 30.1 or later.

To install with `use-package` and `straight.el`:

```emacs-lisp
(use-package labels
  :straight (:type git :host github :repo "drusso/labels"))
```

## Quick Start

### Setup

A minimal setup:

```emacs-lisp
(use-package labels
  :straight (:type git :host github :repo "drusso/labels")

  ;; Choose your own prefix. We'll use C-c l for demonstration.
  :bind-keymap ("C-c l" . labels-keymap)

  :config
  (labels-mode 1))
```

### Mode

With `labels-mode` enabled, this will:

- Enable automatic labelling (see [Automatic Labelling](#automatic-labelling))
- Display labels in the mode line

### Labelling

The commands for managing labels on the current buffer are:

| Command               | `labels-keymap` Key | Example Keybinding | Description                                    |
|-----------------------|---------------------|--------------------|------------------------------------------------|
| `labels-set`          | s                   | C-c l s            | Replace all labels on the current buffer       |
| `labels-add`          | a                   | C-c l a            | Add labels to the current buffer               |
| `labels-remove`       | r                   | C-c l r            | Remove specific labels from the current buffer |
| `labels-clear`        | c                   | C-c l c            | Remove all labels from the current buffer      |
| `labels-kill-buffer`  | k                   | C-c l k            | Kill a labelled buffer                         |
| `labels-kill-buffers` | K                   | C-c l K            | Kill all buffers with labels                   |

When prompted for labels, multiple labels may be specified comma-separated.

A label is any non-blank string. Whitespace is significant: `" a"` and `"a"` are
different labels.

### Automatic Labelling

With `labels-label-functions` configured (and `labels-mode` enabled), labels
specified in the function's return will be automatically added to a buffer's
labels. The return value should be nil (no labels), a single label (a string),
or a list of labels. The function is called with the buffer to be labelled as
current.

For example, we can label terminals based on their major mode:

```emacs-lisp
(defun label-terminals ()
  "A `labels-label-functions' function that labels buffers as terminals."
  (when (derived-mode-p '(eat-mode vterm-mode term-mode eshell-mode))
    "terminal"))

(setopt labels-label-functions #'label-terminals)
```

As another example, we can label using a buffer's directory:

```emacs-lisp
(defun label-code ()
  "A `labels-label-functions' function that labels buffers in the /src/
directory as \"code\" and \"src\"; and buffers in the /tests/ directory
as \"code\" and \"tests\"."
  (if-let* ((dir default-directory))
      (cond ((string-match-p "/src/" dir)
             '("code" "src"))
            ((string-match-p "/tests/" dir)
             '("code" "tests")))))

(setopt labels-label-functions #'label-code)
```

Multiple labelling functions can be used simultaneously:

```emacs-lisp
(setopt labels-label-functions (list #'label-terminals
                                     #'label-code))
```

### Switching Buffers

The commands for switching buffers are:

| Command                   | `labels-keymap` Key | Example Keybinding | Description                                                                |
|---------------------------|---------------------|--------------------|----------------------------------------------------------------------------|
| `labels-switch-to-buffer` | b                   | C-c l b            | Switch to a labelled buffer                                                |
| `labels-pop-to-buffer`    | p                   | C-c l p            | Pop to a labelled buffer                                                   |
| `labels-go-to-buffer`     | g                   | C-c l g            | Go to a labelled buffer, using `labels-go-to-display-function` for display |

`labels-switch-to-buffer` and `labels-pop-to-buffer` are the `labels` variants
of built-ins `switch-to-buffer` and `pop-to-buffer`.

`labels-go-to-buffer` displays buffers using a custom display function, as
configured by `labels-go-to-display-function`. The function should accept a
buffer as its argument and display it. The default selects a window already
displaying the buffer if there is one, otherwise switches to the buffer in the
current window.

### Ibuffer Integration

An Ibuffer integration is provided for viewing, sorting, marking, filtering,
and managing labels. Enable with:

```emacs-lisp
(labels-ibuffer)
```

Enabling the integration has the following effects:

- Registers a `labels` column. This column is available for use in user-defined
  `ibuffer-formats`.
- Adds the following commands to Ibuffer:

  | Command                         | Keybinding | Description                       |
  |---------------------------------|------------|-----------------------------------|
  | `ibuffer-filter-by-labels`      | / #        | Filter by label                   |
  | `ibuffer-do-sort-by-labels`     | s #        | Sort by label                     |
  | `labels-ibuffer-mark-by-labels` | % #        | Mark by label                     |
  | `ibuffer-do-set-labels`         | # s        | Set labels on marked buffers      |
  | `ibuffer-do-add-labels`         | # a        | Add labels to marked buffers      |
  | `ibuffer-do-remove-labels`      | # r        | Remove labels from marked buffers |

  Filtering and marking match buffers that have _all_ of the selected labels
  (note that nested labels do match). To "or" the labels, rather than "and"
  them, use multiple filters and combine then with `ibuffer-or-filter` (`/ |`).
