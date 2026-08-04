;;; gptel-web.el --- Web search tools for gptel

;; Copyright (C) 2026  Victor C. Salas P.

;; Author: Victor C. Salas P. <victor.salas at member.fsf.org>
;; Simple web search tool (MCP search_web alternative) that works and
;; suck less. Search the live web using DuckDuckGo through the local
;; ddgr command.

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

(require 'json)
(require 'subr-x)

;; function that returns the raw search results
(defun vc/ddgr-search (query &optional max-results)
  "Search DuckDuckGo using ddgr and returns the raw search results as
text."
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
        (if (zerop status)
            (with-current-buffer buffer
              (string-trim (buffer-string)))
          (error "ddgr exited with status %d: %s"
                 status
                 (with-current-buffer buffer
                   (buffer-string))))
      (kill-buffer buffer))))

;; gptel tool definition
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
	    "A focused web search query, including product names,
	    versions, and dates when needed.")
    '(:name "max_results"
	    :type integer
	    :description
	    "Maximum number of results to return, usually 3 to 8."
	    :optional t))
   :category "web"
   :confirm t
   :include t))

(add-to-list 'gptel-tools vc/gptel-ddgr-tool)
