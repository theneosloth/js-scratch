;;; js-scratch.el --- A javascript scratch buffer.                 -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Stefan Kuznetsov

;; Author: Stefan Kuznetsov
;; Homepage: https://github.com/theneosloth/js-scratch
;; Keywords: tools
;; Package-Requires: ((emacs "25.1") (websocket "1.12"))
;; Version: 1.0

;; This program is free software; you can redistribute it and/or modify
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

;;

;;; Code:
(require 'websocket)

(defvar js-scratch-opened-websocket nil)
(defvar js-scratch-websocket-server nil)
(defvar js-scratch-received-values nil)
(defvar js-scratch-eval-received-func #'message)

(defvar js-scratch-html "
<!doctype html>
<html lang='en'>
  <head>
    <meta charset='UTF-8'/>
    <title>Scratch</title>
    <script>
      const ws = new WebSocket('ws://localhost:3000');

      let geval = eval;

      //Highjacking console.log so the emacs server sees the output as well.
      let oldLog = console.log;
      console.log = (message) => {
          ws.send(message);
          oldLog(message);
      }

      ws.onopen = (event) => {
          document.title = 'Connected';
      }

      ws.onmessage = (event) => {
          let result;
          try{
              oldLog(event.data);
              result = geval(event.data);
          }
          catch (error){
              result = error.message;
          }

          //This is a very ugly hack to prevent it from sending the value over twice.
          if (event.data.includes('console.log')){
              return;
          }

          // Logs the data on the webpage;
          oldLog(`Sent: ${result} to js-scratch.`);
          ws.send(result);
      }

      ws.onclose = (event) => {
          document.title = 'Disconnected'
      }

    </script>
  </head>
  <body></body>
</html>
")

(defvar js-scratch-html-file (expand-file-name "scratch.html" (file-name-directory load-file-name)))

(defun js-scratch-open-page ()
  "Open a temporary page with a websocket client for 'js-scratch'."
  (interactive)
  (browse-url (make-temp-file "scratch" nil ".html" js-scratch-html)))

(defun js-scratch-start ()
  "Start the 'js-scratch' websocket server."
  (unless js-scratch-websocket-server
    (setq js-scratch-websocket-server
          (websocket-server
           3000
           :host 'local
           :on-message (lambda (_ws frame)
                         (funcall js-scratch-eval-received-func (websocket-frame-text frame)))
           :on-open (lambda (ws)
                      (message "Connected to ws")
                      (setq js-scratch-opened-websocket ws))
           :on-close (lambda (_ws)
                       (message "Closing")
                       (setq js-scratch-opened-websocket nil)))))

  (js-scratch-open-page))


(defun js-scratch-stop ()
  "Stop the 'js-scratch' websocket server."
  (websocket-server-close js-scratch-websocket-server)
  (setq js-scratch-websocket-server nil))

(defun js-scratch-eval (code)
  "Send CODE over the websocket For an eval."
  (if js-scratch-opened-websocket
      (websocket-send-text js-scratch-opened-websocket code)
    (message "No websocket open.")))

(defun js-scratch-eval-last-line-or-region ()
  "Call the browser eval function on the current line or selected region."
  (interactive)
  (setq js-scratch-eval-received-func #'message)
  (if (use-region-p)
      (js-scratch-eval
       (buffer-substring-no-properties (region-beginning) (region-end)))
    (js-scratch-eval (thing-at-point 'line t))))

;; Very ugly code duplication
(defun js-scratch-eval-print-last-line-or-region ()
  "Call the browser eval function on the current line or selected region."
  (interactive)
  (setq js-scratch-eval-received-func #'(lambda (&rest args) (insert "\n") (apply #'insert args)))
  (if (use-region-p)
      (js-scratch-eval
       (buffer-substring-no-properties (region-beginning) (region-end)))
    (js-scratch-eval (thing-at-point 'line t))))

(defun create-js-scratch-buffer ()
  "Create the 'js-scratch' buffer."
  (if (get-buffer "*js-scratch*")
      (switch-to-buffer "*js-scratch*")

    (let ((buffer (generate-new-buffer "*js-scratch*")))
      (switch-to-buffer buffer)
      (js-mode)
      (insert "// C-x C-e to show the result in the minibuffer.\n")
      (insert "// C-j to print the value into current buffer.\n")
      (use-local-map (copy-keymap js-mode-map))
      (local-set-key (kbd "C-x C-e") 'js-scratch-eval-last-line-or-region)
      (local-set-key (kbd "C-j") 'js-scratch-eval-print-last-line-or-region))))

(defun check-if-js-scratch-closed ()
  "Stops the 'js-scratch' server when the buffer is closed."
  (unless (get-buffer "*js-scratch*")
    (message "js-scratch server stopped.")
    (remove-hook 'buffer-list-update-hook #'check-if-js-scratch-closed)
    (js-scratch-stop)))

;;;###autoload
(defun js-scratch ()
  "Start the 'js-scratch' server and opens the buffer."
  (interactive)
  (js-scratch-start)
  (create-js-scratch-buffer)
  (add-hook 'buffer-list-update-hook #'check-if-js-scratch-closed))

(provide 'js-scratch)
;;; js-scratch.el ends here
