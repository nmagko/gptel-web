;;; gptel-web.el --- Web tools for gptel

;; Copyright (C) 2026  Victor C. Salas P.

;; Author: Victor C. Salas P. <victor.salas at member.fsf.org>
;; Search the web with ddgr and retrieve public web pages.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(require 'shr)
(require 'subr-x)
(require 'url)
(require 'url-http)

;; function that returns the raw search results.
(defun vc/ddgr-search (query &optional max-results)
  "Search DuckDuckGo using ddgr and return raw search results as text."
  (let* ((n (or max-results 5))
         (buffer (generate-new-buffer " *ddgr*"))
         (status
          (call-process
           "ddgr"
           nil
           buffer
           nil
           "--np"
           "--num" (number-to-string n)
           query)))
    (unwind-protect
        (if (and (integerp status)
                 (zerop status))
            (with-current-buffer buffer
              (string-trim (buffer-string)))
          (error "ddgr exited with status %s: %s"
                 status
                 (with-current-buffer buffer
                   (buffer-string))))
      (kill-buffer buffer))))

;; gptel search tool definition.
(defvar vc/gptel-ddgr-tool
  (gptel-make-tool
   :name "search_web"
   :function #'vc/ddgr-search
   :description
   "Search the live web using DuckDuckGo through the local ddgr command.
Use this for current information, recent documentation, release notes,
news, version-specific behavior, and facts that may have changed.
Returns search-result titles, domains, URLs, and snippets."
   :args
   (list
    '(:name "query"
	    :type string
	    :description
	    "A focused web search query, including product names, versions, and dates when needed.")
    '(:name "max_results"
	    :type integer
	    :description
	    "Maximum number of results to return, usually 3 to 8."
	    :optional t))
   :category "web"
   :confirm t
   :include t))

(add-to-list 'gptel-tools vc/gptel-ddgr-tool)

;; URL retrieval.
(defvar vc/gptel-web-timeout 20
  "Seconds to wait while retrieving a URL.")

(defvar vc/gptel-web-max-characters 100000
  "Maximum number of characters returned by `vc/gptel-fetch-url'.")

(defvar vc/gptel-web-max-response-bytes (* 5 1024 1024)
  "Maximum accepted HTTP response body size in bytes.")

(defun vc/gptel-web--validate-url (url)
  "Return URL if it is a public HTTP or HTTPS URL."
  (let* ((parsed (url-generic-parse-url url))
         (scheme (downcase (or (url-type parsed) "")))
         (host (downcase (or (url-host parsed) ""))))
    (unless (member scheme '("http" "https"))
      (error "Only HTTP and HTTPS URLs are allowed"))
    (when (or (string-empty-p host)
              (url-user parsed)
              (string-match-p ":" host)
              (string-match-p "\\(?:\\`localhost\\|\\.local\\'\\)" host)
              (string-match-p
               "\\`\\(?:0\\|10\\|127\\|169\\.254\\|192\\.168\\)\\."
               host)
              (string-match-p
               "\\`172\\.\\(?:1[6-9]\\|2[0-9]\\|3[01]\\)\\."
               host))
      (error "Local or private URL is not allowed: %s" url)))
  url)

(defun vc/gptel-web--decode-text (text charset)
  "Decode HTTP body TEXT using CHARSET, defaulting to UTF-8."
  (let* ((coding (and charset (intern-soft (downcase charset))))
         (decoded (decode-coding-string
                   text
                   (if (and coding (coding-system-p coding))
                       coding
                     'utf-8))))
    ;; Replace undecodable raw bytes and unsafe control characters.
    (apply #'string
           (mapcar (lambda (char)
                     (cond
                      ((eq (char-charset char) 'eight-bit) #xfffd)
                      ((and (< char 32)
                            (not (memq char '(9 10 13))))
                       ?\s)
                      (t char)))
                   decoded))))

(defun vc/gptel-web--html-to-text (html)
  "Convert HTML to readable text."
  (with-temp-buffer
    (insert html)
    (let ((document (libxml-parse-html-region (point-min) (point-max))))
      (erase-buffer)
      (shr-insert-document document)
      (string-trim (buffer-string)))))

(defun vc/gptel-fetch-url (url &optional max-characters)
  "Retrieve URL and return its text content. HTML is converted to plain
text. Markdown, JSON, XML, and plain text are returned directly.
MAX-CHARACTERS cannot exceed `vc/gptel-web-max-characters'."
  (vc/gptel-web--validate-url url)
  (let* ((limit (max 1 (min (or max-characters
                                vc/gptel-web-max-characters)
                            vc/gptel-web-max-characters)))
         (url-request-extra-headers
          '(("User-Agent" . "gptel-web/1.0")))
         (buffer (url-retrieve-synchronously
                  url t t vc/gptel-web-timeout)))
    (unless buffer
      (error "Failed to retrieve URL: %s" url))
    (unwind-protect
        (with-current-buffer buffer
          (let* ((status (or url-http-response-status 0))
                 (header-end
                  (or (and (boundp 'url-http-end-of-headers)
                           url-http-end-of-headers)
                      (save-excursion
                        (goto-char (point-min))
                        (and (re-search-forward "\r?\n\r?\n" nil t)
                             (point)))))
                 (content-type-header
                  (save-excursion
                    (goto-char (point-min))
                    (if (re-search-forward
                         "^Content-[Tt]ype:[ \t]*\\([^\r\n]+\\)"
                         header-end t)
                        (downcase (match-string 1))
                      "")))
                 (content-type
                  (string-trim
                   (car (split-string content-type-header ";"))))
                 (charset
                  (and (string-match
                        "charset=[\"']?\\([^;\"'[:space:]]+\\)"
                        content-type-header)
                       (match-string 1 content-type-header)))
                 (final-url
                  (if (and (boundp 'url-current-object)
                           url-current-object)
                      (url-recreate-url url-current-object)
                    url))
                 text)
            (unless (and header-end (<= 200 status 299))
              (error "HTTP %s while retrieving %s" status url))
            (vc/gptel-web--validate-url final-url)
            (when (> (- (point-max) header-end)
                     vc/gptel-web-max-response-bytes)
              (error "Response exceeds the %s-byte limit"
                     vc/gptel-web-max-response-bytes))
            (let ((body
                   (vc/gptel-web--decode-text
                    (buffer-substring-no-properties
                     header-end (point-max))
                    charset)))
              (cond
               ((string-match-p
                 "\\`\\(?:text/html\\|application/xhtml+xml\\)"
                 content-type)
                (setq text (vc/gptel-web--html-to-text body)))
               ((or (string-prefix-p "text/" content-type)
                    (string-match-p
                     "\\`application/\\(?:json\\|xml\\|.*+json\\|.*+xml\\)"
                     content-type))
                (setq text (string-trim body)))
               ((string= content-type "application/pdf")
                (error "PDF extraction is not supported yet"))
               (t
                (error "Unsupported content type: %s"
                       (if (string-empty-p content-type)
                           "unknown"
                         content-type)))))
            (when (> (length text) limit)
              (setq text
                    (concat (substring text 0 limit)
                            "\n\n[Content truncated by gptel-web]")))
            (format "URL: %s\nContent-Type: %s\n\n%s"
                    final-url content-type text)))
      (kill-buffer buffer))))

;; gptel URL retrieval tool definition.
(defvar vc/gptel-fetch-url-tool
  (gptel-make-tool
   :name "fetch_url"
   :function #'vc/gptel-fetch-url
   :description
   "Retrieve a known public HTTP or HTTPS URL and return readable text.
Use this after search_web to read a selected result. Local and private
network URLs are forbidden. PDF extraction is not supported yet."
   :args
   (list
    '(:name "url"
	    :type string
	    :description "Public HTTP or HTTPS URL to retrieve.")
    '(:name "max_characters"
	    :type integer
	    :description "Maximum characters to return, up to 100000."
	    :optional t))
   :category "web"
   :confirm t
   :include t))

(add-to-list 'gptel-tools vc/gptel-fetch-url-tool)

(provide 'gptel-web)
