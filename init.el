;;; init.el --- Emacs configuration -*- lexical-binding: t; -*-

;; Package setup
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; Evil mode
(use-package evil
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-respect-visual-line-mode t)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; Magit with Evil keybindings
(use-package magit
  :commands (magit-status magit-dispatch))

;; Terminal (vterm)
(use-package vterm
  :commands vterm
  :config
  (setq vterm-max-scrollback 10000))

;; GDB integration (current line highlight)
(use-package gdb-mi
  :ensure nil
  :commands (gdb gdb-many-windows)
  :config
  (setq gdb-many-windows t
        gdb-show-main t
        gdb-use-separate-io-buffer t
        gdb-highlight-current-line t))

;; C++ highlights
(use-package modern-cpp-font-lock
  :hook (c++-mode . modern-c++-font-lock-mode))

;; Ace Jump
(use-package ace-jump-mode
  :bind ("C-c j" . ace-jump-mode))

;; LSP for C/C++ (clangd)
(use-package lsp-mode
  :commands lsp
  :hook ((c-mode c++-mode) . lsp)
  :init
  (setq lsp-keymap-prefix "C-c l")
  :config
  (setq lsp-enable-snippet t
        lsp-headerline-breadcrumb-enable t
        lsp-enable-symbol-highlighting t))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :hook (lsp-mode . lsp-ui-mode)
  :config
  (setq lsp-ui-doc-enable t
        lsp-ui-doc-position 'at-point
        lsp-ui-sideline-enable t
        lsp-ui-sideline-show-hover t))

(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-minimum-prefix-length 1
        company-idle-delay 0.1))

;; Persist history between runs
(use-package savehist
  :ensure nil
  :init
  (setq history-length 200
        savehist-additional-variables '(search-ring regexp-search-ring))
  :config
  (savehist-mode 1))

(use-package recentf
  :ensure nil
  :config
  (setq recentf-max-saved-items 200
        recentf-max-menu-items 25)
  (recentf-mode 1))

(use-package saveplace
  :ensure nil
  :config
  (save-place-mode 1))

;; Command: open GDB + Neotree tabs for a path
(require 'cl-lib)
(defun my/open-gdb-and-neotree-tabs (path)
  "Open GDB (mi) and Neotree for PATH in the current tab."
  (interactive "DProject path: ")
  (let ((project-path (file-name-as-directory (expand-file-name path))))
    (tab-bar-rename-tab "gdb")
    (let ((default-directory project-path))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (setq gdb-many-windows t
              gdb-show-main t)
        (gdb "gdb -i=mi")
        (gdb-many-windows t)))
    (let ((default-directory project-path))
      (require 'neotree)
      (neotree-dir project-path)
      (neotree-show))
    ))

;; Project tree (left side)
(use-package neotree
  :bind ("C-c n" . neotree-toggle)
  :config
  (setq neo-window-position 'left
        neo-window-width 32
        neo-theme 'arrow
        neo-smart-open t
        neo-window-fixed-size nil)
  (defun my/neotree--gdb-cli-buffer ()
    "Return the active GDB CLI buffer, if any."
    (or (get-buffer "*gud*")
        (get-buffer "*gdb*")
        (get-buffer "*gdb-mi*")))

  (defun my/tab-bar--select-tab-for-buffer (buffer)
    "Select the tab containing BUFFER. Return t if found."
    (cond
     ((fboundp 'tab-bar-get-buffer-tab)
      (let ((tab (tab-bar-get-buffer-tab buffer)))
        (when tab
          (tab-bar-select-tab-by-name (alist-get 'name tab))
          t)))
     (t
      (let ((tabs (tab-bar-tabs))
            (found nil))
        (while (and tabs (not found))
          (let* ((tab (car tabs))
                 (buffers (alist-get 'buffers tab))
                 (name (alist-get 'name tab)))
            (when (memq buffer buffers)
              (tab-bar-select-tab-by-name name)
              (setq found t)))
          (setq tabs (cdr tabs)))
        found))))

  (defun my/neotree-open-file-in-new-tab (&rest _)
    "Open the selected file in a new tab."
    (let ((path (neo-buffer--get-filename-current-line)))
      (when (and path (file-exists-p path))
        (let* ((filebuf (find-file-noselect path))
               (found (my/tab-bar--select-tab-for-buffer filebuf)))
          (unless found
            (tab-bar-new-tab))
          (switch-to-buffer filebuf)
          (when (fboundp 'neo-global--window-exists-p)
            (unless (neo-global--window-exists-p)
              (neotree-show)))
          (let ((gdb-buf (my/neotree--gdb-cli-buffer)))
            (when gdb-buf
              (let ((filewin (get-buffer-window filebuf t)))
                (when filewin
                  (select-window filewin)))
              (let ((bottom-win (or (window-in-direction 'below (selected-window))
                                    (split-window (selected-window) -15 'below))))
                (when bottom-win
                  (set-window-buffer bottom-win gdb-buf)))))
          (let ((filewin (get-buffer-window filebuf t)))
            (when filewin
              (select-window filewin)))))))
  (advice-add 'neo-open-file :override #'my/neotree-open-file-in-new-tab))

(tab-bar-mode 1)
(defun my/tab-bar-rename-to-buffer ()
  "Rename current tab to buffer file name or *gdb*."
  (let* ((buf (current-buffer))
         (name (buffer-name buf))
         (file (buffer-file-name buf))
         (tab-name (cond
                    ((string-match-p "\\*gdb\\*" name) "*gdb*")
                    (file (file-name-nondirectory file))
                    (t nil))))
    (when (and tab-name
               (not (eq major-mode 'neotree-mode))
               (not (string= tab-name (alist-get 'name (tab-bar--current-tab)))))
      (tab-bar-rename-tab tab-name))))

(add-hook 'buffer-list-update-hook #'my/tab-bar-rename-to-buffer)
(with-eval-after-load 'neotree
  (add-hook 'after-init-hook
            (lambda ()
              (unless (neo-global--window-exists-p)
                (neotree-show)))))

;; Theme: dracula style
(use-package dracula-theme
  :config
  (load-theme 'dracula t))

;; Basic UI tweaks (keep minimal)
(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(provide 'init)
;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
