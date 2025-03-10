;;; seq.el --- Sequence manipulation functions  -*- lexical-binding: t -*-

;; Copyright (C) 2014-2022 Free Software Foundation, Inc.

;; Author: Nicolas Petton <nicolas@petton.fr>
;; Keywords: sequences
;; Version: 2.23
;; Package: seq

;; Maintainer: emacs-devel@gnu.org

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Sequence-manipulation functions that complement basic functions
;; provided by subr.el.
;;
;; All functions are prefixed with "seq-".
;;
;; All provided functions work on lists, strings and vectors.
;;
;; Functions taking a predicate or iterating over a sequence using a
;; function as argument take the function as their first argument and
;; the sequence as their second argument.  All other functions take
;; the sequence as their first argument.
;;
;; While seq.el version 1.8 is in GNU ELPA for convenience, seq.el
;; version 2.0 requires Emacs>=25.1.
;;
;; seq.el can be extended to support new type of sequences.  Here are
;; the generic functions that must be implemented by new seq types:
;; - `seq-elt'
;; - `seq-length'
;; - `seq-do'
;; - `seqp'
;; - `seq-subseq'
;; - `seq-into-sequence'
;; - `seq-copy'
;; - `seq-into'
;;
;; All functions are tested in test/lisp/emacs-lisp/seq-tests.el

;;; Code:

(eval-when-compile (require 'cl-generic))

;; We used to use some sequence functions from cl-lib, but this
;; dependency was swapped around so that it's easier to make seq.el
;; preloaded.  See also Bug#39761#26.

(defmacro seq-doseq (spec &rest body)
  "Loop over a sequence.
Evaluate BODY with VAR bound to each element of SEQUENCE, in turn.

Similar to `dolist' but can be applied to lists, strings, and vectors.

\(fn (VAR SEQUENCE) BODY...)"
  (declare (indent 1) (debug ((symbolp form &optional form) body)))
  `(seq-do (lambda (,(car spec))
             ,@body)
           ,(cadr spec)))

(pcase-defmacro seq (&rest patterns)
  "Build a `pcase' pattern that matches elements of SEQUENCE.

The `pcase' pattern will match each element of PATTERNS against the
corresponding element of SEQUENCE.

Extra elements of the sequence are ignored if fewer PATTERNS are
given, and the match does not fail."
  `(and (pred seqp)
        ,@(seq--make-pcase-bindings patterns)))

(defmacro seq-let (args sequence &rest body)
  "Bind the variables in ARGS to the elements of SEQUENCE, then evaluate BODY.

ARGS can also include the `&rest' marker followed by a variable
name to be bound to the rest of SEQUENCE."
  (declare (indent 2) (debug (sexp form body)))
  `(pcase-let ((,(seq--make-pcase-patterns args) ,sequence))
     ,@body))

(defmacro seq-setq (args sequence)
  "Assign to the variables in ARGS the elements of SEQUENCE.

ARGS can also include the `&rest' marker followed by a variable
name to be bound to the rest of SEQUENCE."
  (declare (debug (sexp form)))
  `(pcase-setq ,(seq--make-pcase-patterns args) ,sequence))


;;; Basic seq functions that have to be implemented by new sequence types
(cl-defgeneric seq-elt (sequence n)
  "Return Nth element of SEQUENCE."
  (elt sequence n))

;; Default gv setters for `seq-elt'.
;; It can be a good idea for new sequence implementations to provide a
;; "gv-setter" for `seq-elt'.
(cl-defmethod (setf seq-elt) (store (sequence array) n)
  (aset sequence n store))

(cl-defmethod (setf seq-elt) (store (sequence cons) n)
  (setcar (nthcdr n sequence) store))

(cl-defgeneric seq-length (sequence)
  "Return the number of elements of SEQUENCE."
  (length sequence))

(defun seq-first (sequence)
  "Return the first element of SEQUENCE."
  (seq-elt sequence 0))

(defun seq-rest (sequence)
  "Return a sequence of the elements of SEQUENCE except the first one."
  (seq-drop sequence 1))

(cl-defgeneric seq-do (function sequence)
  "Apply FUNCTION to each element of SEQUENCE, presumably for side effects.
Return SEQUENCE."
  (mapc function sequence))

(defalias 'seq-each #'seq-do)

(defun seq-do-indexed (function sequence)
  "Apply FUNCTION to each element of SEQUENCE and return nil.
Unlike `seq-map', FUNCTION takes two arguments: the element of
the sequence, and its index within the sequence."
  (let ((index 0))
    (seq-do (lambda (elt)
              (funcall function elt index)
              (setq index (1+ index)))
            sequence))
  nil)

(cl-defgeneric seqp (object)
  "Return non-nil if OBJECT is a sequence, nil otherwise."
  (sequencep object))

(cl-defgeneric seq-copy (sequence)
  "Return a shallow copy of SEQUENCE."
  (copy-sequence sequence))

;;;###autoload
(cl-defgeneric seq-subseq (sequence start &optional end)
  "Return the sequence of elements of SEQUENCE from START to END.
END is exclusive.

If END is omitted, it defaults to the length of the sequence.  If
START or END is negative, it counts from the end.  Signal an
error if START or END are outside of the sequence (i.e too large
if positive or too small if negative)."
  (cond
   ((or (stringp sequence) (vectorp sequence)) (substring sequence start end))
   ((listp sequence)
    (let (len
          (orig-start start)
          (orig-end end))
      (and end (< end 0) (setq end (+ end (setq len (length sequence)))))
      (if (< start 0) (setq start (+ start (or len (setq len (length sequence))))))
      (unless (>= start 0)
        (error "Start index out of bounds: %s" orig-start))
      (when (> start 0)
        (setq sequence (nthcdr (1- start) sequence))
        (unless sequence
          (error "Start index out of bounds: %s" orig-start))
        (setq sequence (cdr sequence)))
      (if end
          (let ((n (- end start)))
            (when (or (< n 0)
                      (if len
                          (> end len)
                        (and (> n 0) (null (nthcdr (1- n) sequence)))))
              (error "End index out of bounds: %s" orig-end))
            (take n sequence))
        (copy-sequence sequence))))
   (t (error "Unsupported sequence: %s" sequence))))


(cl-defgeneric seq-map (function sequence)
  "Return the result of applying FUNCTION to each element of SEQUENCE."
  (let (result)
    (seq-do (lambda (elt)
              (push (funcall function elt) result))
            sequence)
    (nreverse result)))

(defun seq-map-indexed (function sequence)
  "Return the result of applying FUNCTION to each element of SEQUENCE.
Unlike `seq-map', FUNCTION takes two arguments: the element of
the sequence, and its index within the sequence."
  (let ((index 0))
    (seq-map (lambda (elt)
               (prog1
                   (funcall function elt index)
                 (setq index (1+ index))))
             sequence)))


;; faster implementation for sequences (sequencep)
(cl-defmethod seq-map (function (sequence sequence))
  (mapcar function sequence))

(cl-defgeneric seq-mapn (function sequence &rest sequences)
  "Like `seq-map' but FUNCTION is mapped over all SEQUENCES.
The arity of FUNCTION must match the number of SEQUENCES, and the
mapping stops on the shortest sequence.
Return a list of the results.

\(fn FUNCTION SEQUENCES...)"
  (let ((result nil)
        (sequences (seq-map (lambda (s)
                              (seq-into s 'list))
                            (cons sequence sequences))))
    (while (not (memq nil sequences))
      (push (apply function (seq-map #'car sequences)) result)
      (setq sequences (seq-map #'cdr sequences)))
    (nreverse result)))

(cl-defgeneric seq-drop (sequence n)
  "Remove the first N elements of SEQUENCE and return the result.
The result is a sequence of the same type as SEQUENCE.

If N is a negative integer or zero, SEQUENCE is returned."
  (if (<= n 0)
      sequence
    (let ((length (seq-length sequence)))
      (seq-subseq sequence (min n length) length))))

;;;###autoload
(cl-defgeneric seq-take (sequence n)
  "Take the first N elements of SEQUENCE and return the result.
The result is a sequence of the same type as SEQUENCE.

If N is a negative integer or zero, an empty sequence is
returned."
  (seq-subseq sequence 0 (min (max n 0) (seq-length sequence))))

(cl-defgeneric seq-drop-while (pred sequence)
  "Remove the successive elements of SEQUENCE for which PRED returns non-nil.
PRED is a function of one argument.  The result is a sequence of
the same type as SEQUENCE."
  (seq-drop sequence (seq--count-successive pred sequence)))

(cl-defgeneric seq-take-while (pred sequence)
  "Take the successive elements of SEQUENCE for which PRED returns non-nil.
PRED is a function of one argument.  The result is a sequence of
the same type as SEQUENCE."
  (seq-take sequence (seq--count-successive pred sequence)))

(cl-defgeneric seq-empty-p (sequence)
  "Return non-nil if the SEQUENCE is empty, nil otherwise."
  (= 0 (seq-length sequence)))

(cl-defgeneric seq-sort (pred sequence)
  "Sort SEQUENCE using PRED as comparison function.
The result is a sequence of the same type as SEQUENCE."
  (let ((result (seq-sort pred (append sequence nil))))
    (seq-into result (type-of sequence))))

(cl-defmethod seq-sort (pred (list list))
  (sort (seq-copy list) pred))

;;;###autoload
(defun seq-sort-by (function pred sequence)
  "Sort SEQUENCE using PRED as a comparison function.
Elements of SEQUENCE are transformed by FUNCTION before being
sorted.  FUNCTION must be a function of one argument."
  (seq-sort (lambda (a b)
              (funcall pred
                       (funcall function a)
                       (funcall function b)))
            sequence))

(cl-defgeneric seq-reverse (sequence)
  "Return a sequence with elements of SEQUENCE in reverse order."
  (let ((result '()))
    (seq-map (lambda (elt)
               (push elt result))
             sequence)
    (seq-into result (type-of sequence))))

;; faster implementation for sequences (sequencep)
(cl-defmethod seq-reverse ((sequence sequence))
  (reverse sequence))

(cl-defgeneric seq-concatenate (type &rest sequences)
  "Concatenate SEQUENCES into a single sequence of type TYPE.
TYPE must be one of following symbols: vector, string or list.

\n(fn TYPE SEQUENCE...)"
  (setq sequences (mapcar #'seq-into-sequence sequences))
  (pcase type
    ('vector (apply #'vconcat sequences))
    ('string (apply #'concat sequences))
    ('list (apply #'append (append sequences '(nil))))
    (_ (error "Not a sequence type name: %S" type))))

(cl-defgeneric seq-into-sequence (sequence)
  "Convert SEQUENCE into a sequence.

The default implementation is to signal an error if SEQUENCE is not a
sequence, specific functions should be implemented for new types
of sequence."
  (unless (sequencep sequence)
    (error "Cannot convert %S into a sequence" sequence))
  sequence)

(cl-defgeneric seq-into (sequence type)
  "Concatenate the elements of SEQUENCE into a sequence of type TYPE.
TYPE can be one of the following symbols: vector, string or
list."
  (pcase type
    (`vector (seq--into-vector sequence))
    (`string (seq--into-string sequence))
    (`list (seq--into-list sequence))
    (_ (error "Not a sequence type name: %S" type))))

;;;###autoload
(cl-defgeneric seq-filter (pred sequence)
  "Return a list of all elements for which (PRED element) is non-nil in SEQUENCE."
  (let ((exclude (make-symbol "exclude")))
    (delq exclude (seq-map (lambda (elt)
                             (if (funcall pred elt)
                                 elt
                               exclude))
                           sequence))))

;;;###autoload
(cl-defgeneric seq-remove (pred sequence)
  "Return a list of all the elements for which (PRED element) is nil in SEQUENCE."
  (seq-filter (lambda (elt) (not (funcall pred elt)))
              sequence))

;;;###autoload
(cl-defgeneric seq-reduce (function sequence initial-value)
  "Reduce the function FUNCTION across SEQUENCE, starting with INITIAL-VALUE.

Return the result of calling FUNCTION with INITIAL-VALUE and the
first element of SEQUENCE, then calling FUNCTION with that result
and the second element of SEQUENCE, then with that result and the
third element of SEQUENCE, etc.  FUNCTION will be called with
INITIAL-VALUE (and then the accumulated value) as the first
argument, and the elements from SEQUENCE as the second argument.

If SEQUENCE is empty, return INITIAL-VALUE and FUNCTION is not called."
  (if (seq-empty-p sequence)
      initial-value
    (let ((acc initial-value))
      (seq-doseq (elt sequence)
        (setq acc (funcall function acc elt)))
      acc)))

;;;###autoload
(cl-defgeneric seq-every-p (pred sequence)
  "Return non-nil if (PRED element) is non-nil for all elements of SEQUENCE."
  (catch 'seq--break
    (seq-doseq (elt sequence)
      (or (funcall pred elt)
          (throw 'seq--break nil)))
    t))

;;;###autoload
(cl-defgeneric seq-some (pred sequence)
  "Return non-nil if PRED is satisfied for at least one element of SEQUENCE.
If so, return the first non-nil value returned by PRED."
  (catch 'seq--break
    (seq-doseq (elt sequence)
      (let ((result (funcall pred elt)))
        (when result
          (throw 'seq--break result))))
    nil))

;;;###autoload
(cl-defgeneric seq-find (pred sequence &optional default)
  "Return the first element for which (PRED element) is non-nil in SEQUENCE.
If no element is found, return DEFAULT.

Note that `seq-find' has an ambiguity if the found element is
identical to DEFAULT, as it cannot be known if an element was
found or not."
  (catch 'seq--break
    (seq-doseq (elt sequence)
      (when (funcall pred elt)
        (throw 'seq--break elt)))
    default))

(cl-defgeneric seq-count (pred sequence)
  "Return the number of elements for which (PRED element) is non-nil in SEQUENCE."
  (let ((count 0))
    (seq-doseq (elt sequence)
      (when (funcall pred elt)
        (setq count (+ 1 count))))
    count))

(cl-defgeneric seq-contains (sequence elt &optional testfn)
  "Return the first element in SEQUENCE that is equal to ELT.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (declare (obsolete seq-contains-p "27.1"))
  (seq-some (lambda (e)
              (when (funcall (or testfn #'equal) elt e)
                e))
            sequence))

(cl-defgeneric seq-contains-p (sequence elt &optional testfn)
  "Return non-nil if SEQUENCE contains an element equal to ELT.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
    (catch 'seq--break
      (seq-doseq (e sequence)
        (let ((r (funcall (or testfn #'equal) e elt)))
          (when r
            (throw 'seq--break r))))
      nil))

(cl-defgeneric seq-set-equal-p (sequence1 sequence2 &optional testfn)
  "Return non-nil if SEQUENCE1 and SEQUENCE2 contain the same elements.
This does not depend on the order of the elements.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (and (seq-every-p (lambda (item1) (seq-contains-p sequence2 item1 testfn)) sequence1)
       (seq-every-p (lambda (item2) (seq-contains-p sequence1 item2 testfn)) sequence2)))

;;;###autoload
(cl-defgeneric seq-position (sequence elt &optional testfn)
  "Return the index of the first element in SEQUENCE that is equal to ELT.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (let ((index 0))
    (catch 'seq--break
      (seq-doseq (e sequence)
        (when (funcall (or testfn #'equal) e elt)
          (throw 'seq--break index))
        (setq index (1+ index)))
      nil)))

;;;###autoload
(cl-defgeneric seq-uniq (sequence &optional testfn)
  "Return a list of the elements of SEQUENCE with duplicates removed.
TESTFN is used to compare elements, or `equal' if TESTFN is nil."
  (let ((result '()))
    (seq-doseq (elt sequence)
      (unless (seq-contains-p result elt testfn)
        (setq result (cons elt result))))
    (nreverse result)))

(cl-defmethod seq-uniq ((sequence list) &optional testfn)
  (let ((result nil))
    (if (not testfn)
        ;; Fast path.  If the list is long, use a hash table to speed
        ;; things up even more.
        (let ((l (length sequence)))
          (if (> l 100)
              (let ((hash (make-hash-table :test #'equal :size l)))
                (while sequence
                  (unless (gethash (car sequence) hash)
                    (setf (gethash (car sequence) hash) t)
                    (push (car sequence) result))
                  (setq sequence (cdr sequence))))
            ;; Short list.
            (while sequence
              (unless (member (car sequence) result)
                (push (car sequence) result))
              (pop sequence))))
      ;; Slower path.
      (while sequence
        (unless (seq-find (lambda (elem)
                            (funcall testfn elem (car sequence)))
                          result)
          (push (car sequence) result))
        (pop sequence)))
    (nreverse result)))

(cl-defgeneric seq-mapcat (function sequence &optional type)
  "Concatenate the result of applying FUNCTION to each element of SEQUENCE.
The result is a sequence of type TYPE, or a list if TYPE is nil."
  (apply #'seq-concatenate (or type 'list)
         (seq-map function sequence)))

(cl-defgeneric seq-partition (sequence n)
  "Return list of elements of SEQUENCE grouped into sub-sequences of length N.
The last sequence may contain less than N elements.  If N is a
negative integer or 0, nil is returned."
  (unless (< n 1)
    (let ((result '()))
      (while (not (seq-empty-p sequence))
        (push (seq-take sequence n) result)
        (setq sequence (seq-drop sequence n)))
      (nreverse result))))

;;;###autoload
(cl-defgeneric seq-union (sequence1 sequence2 &optional testfn)
  "Return a list of all elements that appear in either SEQUENCE1 or SEQUENCE2.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (let* ((accum (lambda (acc elt)
                  (if (seq-contains-p acc elt testfn)
                      acc
                    (cons elt acc))))
         (result (seq-reduce accum sequence2
                          (seq-reduce accum sequence1 '()))))
    (nreverse result)))

;;;###autoload
(cl-defgeneric seq-intersection (sequence1 sequence2 &optional testfn)
  "Return a list of the elements that appear in both SEQUENCE1 and SEQUENCE2.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (seq-reduce (lambda (acc elt)
                (if (seq-contains-p sequence2 elt testfn)
                    (cons elt acc)
                  acc))
              (seq-reverse sequence1)
              '()))

(cl-defgeneric seq-difference (sequence1 sequence2 &optional testfn)
  "Return a list of the elements that appear in SEQUENCE1 but not in SEQUENCE2.
Equality is defined by TESTFN if non-nil or by `equal' if nil."
  (seq-reduce (lambda (acc elt)
                (if (seq-contains-p sequence2 elt testfn)
                    acc
                  (cons elt acc)))
              (seq-reverse sequence1)
              '()))

;;;###autoload
(cl-defgeneric seq-group-by (function sequence)
  "Apply FUNCTION to each element of SEQUENCE.
Separate the elements of SEQUENCE into an alist using the results as
keys.  Keys are compared using `equal'."
  (seq-reduce
   (lambda (acc elt)
     (let* ((key (funcall function elt))
            (cell (assoc key acc)))
       (if cell
           (setcdr cell (push elt (cdr cell)))
         (push (list key elt) acc))
       acc))
   (seq-reverse sequence)
   nil))

(cl-defgeneric seq-min (sequence)
  "Return the smallest element of SEQUENCE.
SEQUENCE must be a sequence of numbers or markers."
  (apply #'min (seq-into sequence 'list)))

;;;###autoload
(cl-defgeneric seq-max (sequence)
  "Return the largest element of SEQUENCE.
SEQUENCE must be a sequence of numbers or markers."
  (apply #'max (seq-into sequence 'list)))

(defun seq--count-successive (pred sequence)
  "Count successive elements for which (PRED element) is non-nil in SEQUENCE."
  (let ((n 0)
        (len (seq-length sequence)))
    (while (and (< n len)
                (funcall pred (seq-elt sequence n)))
      (setq n (+ 1 n)))
    n))

(defun seq--make-pcase-bindings (args)
  "Return list of bindings of the variables in ARGS to the elements of a sequence."
  (let ((bindings '())
        (index 0)
        (rest-marker nil))
    (seq-doseq (name args)
      (unless rest-marker
        (pcase name
          (`&rest
           (progn (push `(app (pcase--flip seq-drop ,index)
                              ,(seq--elt-safe args (1+ index)))
                        bindings)
                  (setq rest-marker t)))
          (_
           (push `(app (pcase--flip seq--elt-safe ,index) ,name) bindings))))
      (setq index (1+ index)))
    bindings))

(defun seq--make-pcase-patterns (args)
  "Return a list of `(seq ...)' pcase patterns from the argument list ARGS."
  (cons 'seq
        (seq-map (lambda (elt)
                   (if (seqp elt)
                       (seq--make-pcase-patterns elt)
                     elt))
                 args)))

;; TODO: make public?
(defun seq--elt-safe (sequence n)
  "Return element of SEQUENCE at the index N.
If no element is found, return nil."
  (ignore-errors (seq-elt sequence n)))

;;;###autoload
(cl-defgeneric seq-random-elt (sequence)
  "Return a random element from SEQUENCE.
Signal an error if SEQUENCE is empty."
  (if (seq-empty-p sequence)
      (error "Sequence cannot be empty")
    (seq-elt sequence (random (seq-length sequence)))))


;;; Optimized implementations for lists

(cl-defmethod seq-drop ((list list) n)
  "Optimized implementation of `seq-drop' for lists."
  (nthcdr n list))

(cl-defmethod seq-take ((list list) n)
  "Optimized implementation of `seq-take' for lists."
  (take n list))

(cl-defmethod seq-drop-while (pred (list list))
  "Optimized implementation of `seq-drop-while' for lists."
  (while (and list (funcall pred (car list)))
    (setq list (cdr list)))
  list)

(cl-defmethod seq-empty-p ((list list))
  "Optimized implementation of `seq-empty-p' for lists."
  (null list))


(defun seq--into-list (sequence)
  "Concatenate the elements of SEQUENCE into a list."
  (if (listp sequence)
      sequence
    (append sequence nil)))

(defun seq--into-vector (sequence)
  "Concatenate the elements of SEQUENCE into a vector."
  (if (vectorp sequence)
      sequence
    (vconcat sequence)))

(defun seq--into-string (sequence)
  "Concatenate the elements of SEQUENCE into a string."
  (if (stringp sequence)
      sequence
    (concat sequence)))

(defun seq-split (sequence length)
  "Split SEQUENCE into a list of sub-sequences of at most LENGTH.
All the sub-sequences will be of LENGTH, except the last one,
which may be shorter."
  (when (< length 1)
    (error "Sub-sequence length must be larger than zero"))
  (let ((result nil)
        (seq-length (length sequence))
        (start 0))
    (while (< start seq-length)
      (push (seq-subseq sequence start
                        (setq start (min seq-length (+ start length))))
            result))
    (nreverse result)))

(provide 'seq)
;;; seq.el ends here
