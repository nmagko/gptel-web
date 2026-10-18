;;; gptel-file.el --- Restricted file creation tool for gptel

;; Copyright (C) 2026  Victor C. Salas P.

;; Author: Victor C. Salas P. <victor.salas at member.fsf.org>
;; Restricted file creation tool for gptel. Saves generated UTF-8 files
;; to a designated output directory.

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

(require 'subr-x)

(defvar vc/gptel-file-directory
  (expand-file-name
   "output/"
   (if (boundp 'vc/gptel-root-path)
       vc/gptel-root-path
     "~/src/g/gptel"))
  "Directory where gptel can create files")

;; function that saves results to file
(defun vc/gptel-create-file (filename content)
  "Create FILENAME containing CONTENT in the permitted directory."
  (unless (and (stringp filename)
               (string-match-p "\\`[[:alnum:]_.-]+\\'" filename)
               (not (member filename '("." ".."))))
    (error "Invalid filename: %s" filename))
  (let* ((dir vc/gptel-file-directory)
         (path (expand-file-name filename dir)))
    (unless (file-directory-p dir)
      (error "Output directory does not exist: %s" dir))
    (when (or (file-exists-p path)
              (file-symlink-p path))
      (error "File already exists: %s" path))
    (with-temp-buffer
      (insert content)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region (point-min) (point-max)
                      path nil 'silent nil 'excl)))
    (format "Created: %s" path)))

;; gptel tool definition
(defvar vc/gptel-file-tool
  (gptel-make-tool
   :name "create_file"
   :function #'vc/gptel-create-file
   :description
   "Create a UTF-8 text file in the designated output directory.
Use this for generated code, scripts, configurations, and documents.
Only a simple filename is accepted, with no paths or subdirectories.
Existing files aren't overwritten."
   :args
   (list
    '(:name "filename"
            :type string
            :description "Output filename, e.g. main.c")
    '(:name "content"
            :type string
            :description "Complete UTF-8 file content"))
   :category "filesystem"
   :confirm t
   :include t))

(add-to-list 'gptel-tools vc/gptel-file-tool)

(provide 'gptel-file)
