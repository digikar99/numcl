#|

This file is a part of NUMCL project.
Copyright (c) 2019 IBM Corporation
SPDX-License-Identifier: LGPL-3.0-or-later

NUMCL is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any
later version.

NUMCL is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
NUMCL.  If not, see <http://www.gnu.org/licenses/>.

|#



#|

While most functions require the custom code for handling the corner cases,
some functions can be implimented with INTERPRET-TYPE, a function that
interprets a form consisting of functions and type specifiers (at the leafs).

|#


(in-package :numcl.impl)

(lisp-namespace:define-namespace inferer (or symbol function) nil "namespace for type inference")

(defun set-type-inferer (name fname)
  (setf (symbol-inferer name)
        fname))

(defun infer-type (name &rest args)
  (if (inferer-boundp name)
      (apply (symbol-inferer name) args)
      (progn
        (warn "Missing type inference function for ~a, defaults to T" name)
        t)))

(defun interpret-type (form)
  "Form is a cons tree in which:
 form : (inferer args*)
 arg  : type | form "
  (ematch form
    ((list* (list 'lambda (list* arg args) body) type types)
     (interpret-type
      `((lambda ,args ,(subst type arg body)) ,@types)))
    ((list (list 'lambda nil body))
     (interpret-type
      body))
    ((list* name types)
     (if (inferer-boundp name)
         (apply #'infer-type
                name
                (mapcar #'interpret-type types))
         form))
    (_
     (if (numberp form)
         (if (realp form)
             `(,(first (ensure-list (type-of form))) ,form ,form)
             'complex)
         form))))

(defun funcall* (fn x &optional (default '*))
  (if (numberp x)
      (handler-case (funcall fn x)
        (floating-point-overflow ()
          '*))
      default))

(defconstant +quater+ (/ pi 2))

;; (interpret-type '(+ (integer 0 100) (integer -10 100))) -> (integer -10 200)

(set-type-inferer
 '+
 (defun add-to-float-type (&rest typespecs)
   (infer-rational-arithmetic-result #'interval-add typespecs 'integer)))

(set-type-inferer
 '-
 (defun sub-to-float-type (first &rest typespecs)
   (if typespecs
       (infer-rational-arithmetic-result #'interval-sub (cons first typespecs) 'integer)
       (infer-rational-arithmetic-result #'interval-mul (list first '(integer -1 -1)) 'integer))))

;; (sub-to-float-type '(integer 3 5))
;; --> (integer -5 -3)

(set-type-inferer
 '*
 (defun mul-to-float-type (&rest typespecs)
   (infer-rational-arithmetic-result #'interval-mul typespecs 'integer)))

;; division may result in ratios; we coerce it into *numcl-default-float-format*

(set-type-inferer
 '/
 (defun div-to-float-type (first &rest typespecs)
   (if typespecs
       (infer-rational-arithmetic-result #'interval-div (cons first typespecs) *numcl-default-float-format*)
       (infer-rational-arithmetic-result #'interval-div (list '(integer 1 1) first) *numcl-default-float-format*))))

(set-type-inferer
 'expt
 (defun expt-to-float-type (&rest typespecs)
   (infer-rational-arithmetic-result #'interval-expt typespecs 'integer)))

(set-type-inferer
 'max
 (defun max-to-float-type (&rest typespecs)
   (infer-rational-arithmetic-result #'interval-max typespecs 'integer)))

(set-type-inferer
 'min
 (defun min-to-float-type (&rest typespecs)
   (infer-rational-arithmetic-result #'interval-min typespecs 'integer)))

;; transcendental functions

(set-type-inferer
 'cos
 (defun cos-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((or (real-subtype _ '*)
          (real-subtype '* _))
      `(,%float%
        ,(coerce -1 %float%)
        ,(coerce 1 %float%)))
     ((real-subtype low high)
      (assert (< low high))
      (let* ((low-next-quater-n (ceiling low +quater+))
             ;; 0+4n->0+4n ; 1+4n->0+4(n+1); 2+4n->0+4(n+1); 3+4n->0+4(n+1)
             (low-next-r (* +quater+ (+ (* 4 (ceiling (- low-next-quater-n 0) 4)) 0)))
             ;; 0+4n->1+4n ; 1+4n->1+4n; 2+4n->1+4(n+1); 3+4n->1+4(n+1)
             ;; (low-next-t (* +quater+ (+ (* 4 (ceiling (- low-next-quater-n 1) 4)) 1)))
             ;; 0+4n->2+4n ; 1+4n->2+4n; 2+4n->2+4n; 3+4n->2+4(n+1)
             (low-next-l (* +quater+ (+ (* 4 (ceiling (- low-next-quater-n 2) 4)) 2)))
             ;; 0+4n->3+4n ; 1+4n->3+4n; 2+4n->3+4n; 3+4n->3+4n
             ;; (low-next-b (* +quater+ (+ (* 4 (ceiling (- low-next-quater-n 3) 4)) 3)))
             (high-previous-quater-n (floor high +quater+))
             ;; 0+4n->0+4n ; 1+4n->0+4n; 2+4n->0+4n; 3+4n->0+4n
             (high-previous-r (* +quater+ (+ (* 4 (floor (- high-previous-quater-n 0) 4)) 0)))
             ;; 0+4n->1+4(n-1) ; 1+4n->1+4n; 2+4n->1+4n; 3+4n->1+4n
             ;; (high-previous-t (* +quater+ (+ (* 4 (floor (- high-previous-quater-n 1) 4)) 1)))
             ;; 0+4n->2+4(n-1) ; 1+4n->2+4(n-1); 2+4n->2+4n; 3+4n->2+4n
             (high-previous-l (* +quater+ (+ (* 4 (floor (- high-previous-quater-n 2) 4)) 2)))
             ;; 0+4n->3+4(n-1) ; 1+4n->3+4(n-1); 2+4n->3+4(n-1); 3+4n->3+4n
             ;; (high-previous-b (* +quater+ (+ (* 4 (floor (- high-previous-quater-n 3) 4)) 3)))
             )
        (flet ((in-range (x) (<= low x high)))
          `(,%float%
            ,(coerce (reduce #'min (remove-if-not #'in-range (list low low-next-r high-previous-r high)) :key #'cos) %float%)
            ,(coerce (reduce #'max (remove-if-not #'in-range (list low low-next-l high-previous-l high)) :key #'cos) %float%)))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'cos-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'cos-inferer)))))

(set-type-inferer 'sin (defun sin-inferer (x) (interpret-type `(cos (- ,x ,+quater+)))))

(set-type-inferer 'tan (defun tan-inferer (x) (interpret-type `(/ (sin ,x) (cos ,x)))))

(set-type-inferer
 'exp
 (defun exp-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype low high)
      (let ((head (float-substitution x :int-result *numcl-default-float-format*)))
        `(,head ,(funcall* 'exp low (coerce 0 head)) ,(funcall* 'exp high))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'exp-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'exp-inferer)))))

(set-type-inferer
 'log
 (defun log-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype low high)
      (let ((head (float-substitution x :int-result *numcl-default-float-format*)))
        ;; when minus, may become complex
        (cond
          ((interval2-< low 0)
           `(complex ,head))
          ((= low 0)
           `(,head * ,(funcall* 'log high)))
          (t
           `(,head ,(funcall* 'log low) ,(funcall* 'log high))))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'log-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'log-inferer)))))

(set-type-inferer
 '%log2
 (defun %log2-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype low high)
      (let ((head (float-substitution x :int-result *numcl-default-float-format*)))
        ;; when minus, may become complex
        (cond
          ((interval2-< low 0)
           `(complex ,head))
          ((= low 0)
           `(,head * ,(funcall* '%log2 high)))
          (t
           `(,head ,(funcall* '%log2 low) ,(funcall* '%log2 high))))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'%log2-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'%log2-inferer)))))

(defun complex-part-inferer (x)
  (declare (trivia:optimizer :trivial))
  (ematch x
    ((real-subtype)
     x)
    ((complex-type element-type)
     element-type)
    ((or-type types)
     (reduce #'union-to-float-type types :key #'complex-part-inferer))
    ((and-type types)
     (reduce #'intersection-to-float-type types :key #'complex-part-inferer))))

(set-type-inferer 'realpart 'complex-part-inferer)
(set-type-inferer 'imagpart 'complex-part-inferer)

(set-type-inferer 'cosh (defun cosh-inferer (x) (interpret-type `(/ (+ (exp ,x) (exp (- ,x))) 2))))

(set-type-inferer 'sinh (defun sinh-inferer (x) (interpret-type `(/ (- (exp ,x) (exp (- ,x))) 2))))

(set-type-inferer 'tanh (defun tanh-inferer (x) (interpret-type `(/ (sinh ,x) (cosh ,x)))))

;; (set-type-inferer 'coth (defun coth-inferer (x) (interpret-type `(/ (cosh ,x) (sinh ,x)))))
;; 
;; (set-type-inferer 'sech (defun cosh-inferer (x) (interpret-type `(/ 2 (+ (exp ,x) (exp (- ,x)))))))
;; 
;; (set-type-inferer 'cosech (defun sinh-inferer (x) (interpret-type `(/ 2 (- (exp ,x) (exp (- ,x)))))))

(set-type-inferer
 'acos
 (defun acos-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype low high)
      (if (and (interval2-< -1 low)
               (interval1-< high 1))
          `(,(float-substitution x :int-result *numcl-default-float-format*)
             ,(funcall* 'acos high)
             ,(funcall* 'acos low))
          `(complex ,(float-substitution x :int-result *numcl-default-float-format*))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'acos-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'acos-inferer)))))

(set-type-inferer
 'asin
 (defun asin-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype low high)
      (if (and (interval2-< -1 low)
               (interval1-< high 1))
          `(,(float-substitution x :int-result *numcl-default-float-format*)
             ,(funcall* 'asin low)
             ,(funcall* 'asin high))
          `(complex ,(float-substitution x :int-result *numcl-default-float-format*))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'asin-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'asin-inferer)))))

(set-type-inferer
 'atan
 (defun atan-inferer (x)
   (ematch x
     ((real-subtype low high)
      (let ((type (float-substitution x :int-result *numcl-default-float-format*)))
        `(,type
          ,(funcall* 'atan low (%coerce -1 type))
          ,(funcall* 'atan high (%coerce -1 type)))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'atan-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'atan-inferer)))))

(set-type-inferer
 'abs
 (defun abs-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype)
      (let ((head (float-substitution x)))
        (union-to-float-type
         (intersection-to-float-type x `(,head ,(coerce 0 head) *))
         (mul-to-float-type
          `(,head ,(coerce -1 head) ,(coerce -1 head))
          (intersection-to-float-type x `(,head * ,(coerce 0 head)))))))
     ((complex-type)
      ;; TBD
      'complex)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'abs-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'abs-inferer)))))

;; floor is same as / except the handling of integer-integer

(set-type-inferer
 'floor
 (defun floor-inferer (x &optional (y '(integer 1 1)))
   (declare (trivia:optimizer :trivial))
   (ematch* (x y)
     (((real-subtype l1 h1) (real-subtype l2 h2))
      `(integer ,@(interval-floor l1 h1 l2 h2)))
     (((or-type types1) (or-type types2))
      (reduce #'union-to-float-type
              (mapcar #'floor-inferer types1 types2)))
     (((and-type types1) (and-type types2))
      (reduce #'intersection-to-float-type
              (mapcar #'floor-inferer types1 types2))))))

(set-type-inferer
 'round
 (defun round-inferer (x &optional (y '(integer 1 1)))
   (declare (trivia:optimizer :trivial))
   (ematch* (x y)
     (((real-subtype l1 h1) (real-subtype l2 h2))
      `(integer ,@(interval-round l1 h1 l2 h2)))
     (((or-type types1) (or-type types2))
      (reduce #'union-to-float-type
              (mapcar #'round-inferer types1 types2)))
     (((and-type types1) (and-type types2))
      (reduce #'intersection-to-float-type
              (mapcar #'round-inferer types1 types2))))))

(set-type-inferer
 'ceiling
 (defun ceiling-inferer (x &optional (y '(integer 1 1)))
   (declare (trivia:optimizer :trivial))
   (ematch* (x y)
     (((real-subtype l1 h1) (real-subtype l2 h2))
      `(integer ,@(interval-ceiling l1 h1 l2 h2)))
     (((or-type types1) (or-type types2))
      (reduce #'union-to-float-type
              (mapcar #'ceiling-inferer types1 types2)))
     (((and-type types1) (and-type types2))
      (reduce #'intersection-to-float-type
              (mapcar #'ceiling-inferer types1 types2))))))

(set-type-inferer
 'truncate
 (defun truncate-inferer (x &optional (y '(integer 1 1)))
   (declare (trivia:optimizer :trivial))
   (ematch* (x y)
     (((real-subtype l1 h1) (real-subtype l2 h2))
      `(integer ,@(interval-truncate l1 h1 l2 h2)))
     (((or-type types1) (or-type types2))
      (reduce #'union-to-float-type
              (mapcar #'truncate-inferer types1 types2)))
     (((and-type types1) (and-type types2))
      (reduce #'intersection-to-float-type
              (mapcar #'truncate-inferer types1 types2))))))

(set-type-inferer 'mod 'intersection-to-float-type)

(set-type-inferer
 'rem
 (defun rem-inferer (x y)
   (declare (trivia:optimizer :trivial))
   ;; floor documentation:
   ;;
   ;; The remainder is an integer if both x and y are integers, is a rational
   ;; if both x and y are rationals, and is a float if either x or y is
   ;; a float.
   ;; 
   (ematch* (x y)
     (((real-subtype) (real-subtype))
      (intersection-to-float-type
       x
       (union-to-float-type
         y
         (mul-to-float-type y `(integer -1 -1)))))
     (((or-type types1) (or-type types2))
      (reduce #'union-to-float-type
              (mapcar #'rem-inferer types1 types2)))
     (((and-type types1) (and-type types2))
      (reduce #'intersection-to-float-type
              (mapcar #'rem-inferer types1 types2))))))


#|
(defun signum         (x) )
(defun cis            (x) )
(defun complex        (x) (map-array #'complex x))
(defun conjugate      (x) )
(defun phase          (x) )
(defun realpart       (x) )
(defun imagpart       (x) )
(defun numerator      (x) )
(defun denominator    (x) )
(defun logcount       (x) )
(defun integer-length (x) )
(defun float          (x) )
|#


(set-type-inferer '=/bit (constantly 'bit))
(set-type-inferer '/=/bit (constantly 'bit))
(set-type-inferer '>=/bit (constantly 'bit))
(set-type-inferer '<=/bit (constantly 'bit))
(set-type-inferer '>/bit (constantly 'bit))
(set-type-inferer '</bit (constantly 'bit))

(set-type-inferer
 'logior
 (defun infer-logior (x y)
   (declare (trivia:optimizer :trivial))
   (labels ((fn (prev now)
              (ematch* (prev now)
                (((integer-subtype l1 h1) (integer-subtype l2 h2))
                 (flet ((integer-length* (x)
                          (if (eq x '*) '* (integer-length x))))
                   `(,(if (or (interval1-< l1 0)
                              (interval1-< l2 0))
                          'signed-byte
                          'unsigned-byte)
                      ,(interval2-max (interval2-max (integer-length* l1)
                                                     (integer-length* h1))
                                      (interval2-max (integer-length* l2)
                                                     (integer-length* h2))))))
                (((or-type types1) _)
                 (simplify-or-types
                  (mapcar (lambda (type) (fn type now)) types1)))
                ((_ (or-type types2))
                 (simplify-or-types
                  (mapcar (lambda (type) (fn prev type)) types2))))))
     (fn x y))))

(set-type-inferer
 'logand
 (defun infer-logand (x y)
   (declare (trivia:optimizer :trivial))
   (labels ((fn (prev now)
              (ematch* (prev now)
                (((integer-subtype l1 h1) (integer-subtype l2 h2))
                 (flet ((integer-length* (x)
                          (if (eq x '*) '* (integer-length x))))
                   `(,(if (and (interval1-< l1 0)
                               (interval1-< l2 0))
                          'signed-byte
                          'unsigned-byte)
                      ,(interval2-min (interval2-max (integer-length* l1)
                                                     (integer-length* h1))
                                      (interval2-max (integer-length* l2)
                                                     (integer-length* h2))))))
                (((or-type types1) _)
                 (simplify-or-types
                  (mapcar (lambda (type) (fn type now)) types1)))
                ((_ (or-type types2))
                 (simplify-or-types
                  (mapcar (lambda (type) (fn prev type)) types2))))))
     (fn x y))))

(set-type-inferer
 'logeqv
 (defun infer-logeqv (x y)
   (declare (trivia:optimizer :trivial))
   (labels ((fn (prev now)
              (ematch* (prev now)
                (((integer-subtype l1 h1) (integer-subtype l2 h2))
                 (flet ((integer-length* (x)
                          (if (eq x '*) '* (integer-length x))))
                   `(signed-byte
                     ,(interval2-max (interval2-max (integer-length* l1)
                                                    (integer-length* h1))
                                     (interval2-max (integer-length* l2)
                                                    (integer-length* h2))))))
                (((or-type types1) _)
                 (simplify-or-types
                  (mapcar (lambda (type) (fn type now)) types1)))
                ((_ (or-type types2))
                 (simplify-or-types
                  (mapcar (lambda (type) (fn prev type)) types2))))))
     (fn x y))))

(set-type-inferer 'logxor 'infer-logeqv)

(set-type-inferer
 'lognot
 (defun infer-lognot (x)
   (declare (trivia:optimizer :trivial))
   (labels ((integer-length* (x)
              (if (eq x '*) '* (integer-length x)))
            (lognot* (x)
              (if (eq x '*) '* (lognot x)))
            (fn (x)
              (ematch x
                ((integer-subtype l1 h1)
                 `(,(if (or (interval1-< (lognot* l1) 0)
                            (interval1-< (lognot* h1) 0))
                        'signed-byte
                        'unsigned-byte)
                    ,(interval2-max (integer-length* l1)
                                    (integer-length* h1))))
                ((or-type types1)
                 (simplify-or-types
                  (mapcar #'fn types1))))))
     (fn x))))

(set-type-inferer 'logandc1 (defun infer-logandc1 (x y) (infer-logand (infer-lognot x) y)))
(set-type-inferer 'logandc2 (defun infer-logandc2 (x y) (infer-logand x (infer-lognot y))))
(set-type-inferer 'logorc1 (defun infer-logorc1 (x y) (infer-logior (infer-lognot x) y)))
(set-type-inferer 'logorc2 (defun infer-logorc2 (x y) (infer-logior x (infer-lognot y))))
(set-type-inferer 'lognand (defun infer-lognand (x y) (infer-lognot (infer-logand x y))))
(set-type-inferer 'lognor  (defun infer-lognor  (x y) (infer-lognot (infer-logior x y))))
  
(set-type-inferer
 'conjugate
 (defun conjugate-inferer (x)
   (declare (trivia:optimizer :trivial))
   (ematch x
     ((real-subtype)
      x)
     ((complex-type)
      x)
     ((or-type types)
      (reduce #'union-to-float-type types :key #'conjugate-inferer))
     ((and-type types)
      (reduce #'intersection-to-float-type types :key #'conjugate-inferer)))))

