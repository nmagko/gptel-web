;;; gptel-project.el --- Restricted project workspace tools

;; Copyright (C) 2026  Victor C. Salas P.

;; Author: Victor C. Salas P. <victor.salas at member.fsf.org>
;; Projects are copies placed under a dedicated workspace directory.

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

(require 'gptel-file)
(require 'cl-lib)
(require 'subr-x)

(defvar vc/gptel-project-directory
  (expand-file-name
   "workspace/"
   (if (boundp 'vc/gptel-root-path)
       vc/gptel-root-path
     "~/src/g/gptel"))
  "Directory containing project copies accessible to gptel")

(defun vc/gptel-project-path (project &optional filename)
  "Return a safe path inside PROJECT for relative FILENAME"
  (unless (and (stringp project)
               (string-match-p "\\`[[:alnum:]_-]+\\'" project))
    (error "Invalid project name: %s" project))
  (let* ((base (expand-file-name vc/gptel-project-directory))
         (root (expand-file-name project base))
         (parts (and filename (split-string filename "/" t)))
         (path root))
    (unless (and (file-directory-p base)
                 (not (file-symlink-p base))
                 (file-directory-p root)
                 (not (file-symlink-p root)))
      (error "Invalid or missing workspace/project directory"))
    (when filename
      (unless (and (stringp filename)
                   (not (string-empty-p filename))
                   (not (file-name-absolute-p filename))
                   (not (string-match-p "\\\\" filename))
                   (cl-every
                    (lambda (part)
                      (and (string-match-p
                            "\\`[[:alnum:]_.-]+\\'" part)
                           (not (member part '("." "..")))))
                    parts)
                   (string= filename (string-join parts "/")))
        (error "Invalid relative filename: %s" filename))
      (dolist (part parts)
        (setq path (expand-file-name part path))
        (when (file-symlink-p path)
          (error "Symbolic links are not permitted: %s" path))))
    path))

(defun vc/gptel-project-list (project)
  "List regular files in PROJECT recursively"
  (let ((root (vc/gptel-project-path project)))
    (mapconcat
     #'identity
     (sort
      (mapcar (lambda (path)
                (file-relative-name path root))
              (directory-files-recursively
               root ".*" nil
               (lambda (dir)
                 (not (file-symlink-p dir)))))
      #'string<)
     "\n")))

(defun vc/gptel-project-read (project filename)
  "Read text FILENAME inside PROJECT"
  (let ((path (vc/gptel-project-path project filename)))
    (unless (file-regular-p path)
      (error "File does not exist: %s" filename))
    (when (> (file-attribute-size (file-attributes path))
             (* 1024 1024))
      (error "File exceeds 1 MiB reading limit"))
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

(defun vc/gptel-project-update (project filename content)
  "Replace existing text FILENAME in PROJECT with CONTENT"
  (let ((path (vc/gptel-project-path project filename)))
    (unless (file-regular-p path)
      (error "File does not exist: %s" filename))
    (unless (stringp content)
      (error "Content must be text"))
    (with-temp-buffer
      (insert content)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region (point-min) (point-max) path)))
    (format "Updated: %s" path)))

(defun vc/gptel-project-create (project filename content)
  "Create a new text FILENAME inside PROJECT"
  (let ((path (vc/gptel-project-path project filename)))
    (unless (stringp content)
      (error "Content must be text"))
    (unless (file-directory-p (file-name-directory path))
      (error "Parent directory must already exist"))
    (when (or (file-exists-p path) (file-symlink-p path))
      (error "File already exists: %s" path))
    (with-temp-buffer
      (insert content)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region (point-min) (point-max)
                      path nil 'silent nil 'excl)))
    (format "Created: %s" path)))

(defun vc/gptel-project-mkdir (project dirname)
  "Create a new directory DIRNAME inside PROJECT."
  (let ((path (vc/gptel-project-path project dirname)))
    (when (or (file-exists-p path) (file-symlink-p path))
      (error "Directory already exists: %s" dirname))
    (unless (file-directory-p (file-name-directory path))
      (error "Parent directory must already exist"))
    (make-directory path)
    (format "Created directory: %s" path)))

(defvar vc/gptel-project-tools
  (list
   (gptel-make-tool
    :name "list_project_files"
    :function #'vc/gptel-project-list
    :description
    "List files recursively in a project copy under workspace/."
    :args
    '((:name "project" :type string
             :description "Project workspace directory name"))
    :category "filesystem"
    :confirm t
    :include t)

   (gptel-make-tool
    :name "read_project_file"
    :function #'vc/gptel-project-read
    :description
    "Read a text file from a project workspace using a relative path."
    :args
    '((:name "project" :type string
             :description "Project workspace directory name")
      (:name "filename" :type string
             :description "Relative path, e.g. src/main.py"))
    :category "filesystem"
    :confirm t
    :include t)

   (gptel-make-tool
    :name "update_project_file"
    :function #'vc/gptel-project-update
    :description
    "Replace an existing project text file with complete updated content. Does not modify other files."
    :args
    '((:name "project" :type string
             :description "Project workspace directory name")
      (:name "filename" :type string
             :description "Relative path to existing file")
      (:name "content" :type string
             :description "Complete replacement file content"))
    :category "filesystem"
    :confirm t
    :include t)

   (gptel-make-tool
    :name "create_project_directory"
    :function #'vc/gptel-project-mkdir
    :description
    "Create one new directory inside an existing project workspace. Parent directory must already exist. Never overwrite."
    :args
    '((:name "project" :type string
             :description "Project workspace directory name")
      (:name "dirname" :type string
             :description "Relative directory path, e.g. src/modules"))
    :category "filesystem"
    :confirm t
    :include t)

   (gptel-make-tool
    :name "create_project_file"
    :function #'vc/gptel-project-create
    :description
    "Create a new text file in an existing project directory. Never overwrite existing files."
    :args
    '((:name "project" :type string
             :description "Project workspace directory name")
      (:name "filename" :type string
             :description "Relative path to new file")
      (:name "content" :type string
             :description "Complete UTF-8 file content"))
    :category "filesystem"
    :confirm t
    :include t)))

(dolist (tool vc/gptel-project-tools)
  (add-to-list 'gptel-tools tool))

(provide 'gptel-project)
