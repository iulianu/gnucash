;; -*-scheme-*- ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; advanced-portfolio.scm
;; by Martijn van Oosterhout (kleptog@svana.org) Feb 2002
;; modified for GnuCash 1.8 by Herbert Thoma (herbie@hthoma.de) Oct 2002
;;
;; Heavily based on portfolio.scm
;; by Robert Merkel (rgmerk@mira.net)
;;
;; This program is free software; you can redistribute it and/or    
;; modify it under the terms of the GNU General Public License as   
;; published by the Free Software Foundation; either version 2 of   
;; the License, or (at your option) any later version.              
;;                                                                  
;; This program is distributed in the hope that it will be useful,  
;; but WITHOUT ANY WARRANTY; without even the implied warranty of   
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    
;; GNU General Public License for more details.                     
;;                                                                  
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 59 Temple Place - Suite 330        Fax:    +1-617-542-2652
;; Boston, MA  02111-1307,  USA       gnu@gnu.org
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (gnucash report advanced-portfolio))

(use-modules (gnucash main)) ;; FIXME: delete after we finish modularizing.
(use-modules (srfi srfi-1))
(use-modules (ice-9 slib))
(use-modules (gnucash gnc-module))

(require 'printf)

(gnc:module-load "gnucash/report/report-system" 0)

(define optname-price-source (N_ "Price Source"))
(define optname-zero-shares (N_ "Include accounts with no shares"))

(define (options-generator)
  (let* ((options (gnc:new-options)) 
         ;; This is just a helper function for making options.
         ;; See gnucash/src/scm/options.scm for details.
         (add-option 
          (lambda (new-option)
            (gnc:register-option options new-option))))

    ;; General Tab
    ;; date at which to report balance
    (gnc:options-add-report-date!
     options gnc:pagename-general 
     (N_ "Date") "a")

    (gnc:options-add-currency! 
     options gnc:pagename-general (N_ "Report Currency") "c")

    (gnc:options-add-price-source! 
     options gnc:pagename-general
     optname-price-source "d" 'pricedb-latest)

    ;; Account tab
    (add-option
     (gnc:make-account-list-option
      gnc:pagename-accounts (N_ "Accounts")
      "b"
      (N_ "Stock Accounts to report on")
      (lambda () (filter gnc:account-is-stock?
                         (gnc:group-get-subaccounts
                          (gnc:get-current-group))))
      (lambda (accounts) (list  #t 
                                (filter gnc:account-is-stock? accounts)))
      #t))

    (gnc:register-option 
     options 
     (gnc:make-simple-boolean-option
      gnc:pagename-accounts optname-zero-shares "e" 
      (N_ "Include accounts that have a zero share balances.")
      #f))
    
    (gnc:options-set-default-section options gnc:pagename-general)      
    options))

;; This is the rendering function. It accepts a database of options
;; and generates an object of type <html-document>.  See the file
;; report-html.txt for documentation; the file report-html.scm
;; includes all the relevant Scheme code. The option database passed
;; to the function is one created by the options-generator function
;; defined above.
(define (advanced-portfolio-renderer report-obj)
  
  ;; These are some helper functions for looking up option values.
  (define (get-op section name)
    (gnc:lookup-option (gnc:report-options report-obj) section name))
  
  (define (get-option section name)
    (gnc:option-value (get-op section name)))
  
  (define (split-account-type? split type)
    (eq? type 
         (gw:enum-<gnc:AccountType>-val->sym (gnc:account-get-type (gnc:split-get-account split)) #f)))

  (define (same-split? s1 s2)
    (string=? (gnc:split-get-guid s1) (gnc:split-get-guid s2)))
  
  (define (table-add-stock-rows table accounts to-date
                                currency price-fn include-empty total-value total-moneyin total-moneyout total-gain)

    (define (table-add-stock-rows-internal accounts odd-row?)
      (if (null? accounts) total-value
          (let* ((row-style (if odd-row? "normal-row" "alternate-row"))
                 (current (car accounts))
                 (rest (cdr accounts))
                 (name (gnc:account-get-name current))
                 (commodity (gnc:account-get-commodity current))
                 (ticker-symbol (gnc:commodity-get-mnemonic commodity))
                 (listing (gnc:commodity-get-namespace commodity))
                 (unit-collector (gnc:account-get-comm-balance-at-date
                                  current to-date #f))
                 (units (cadr (unit-collector 'getpair commodity #f)))
                 (totalunits 0.0)
                 (totalunityears 0.0)

                 ;; Counter to keep track of stuff
                 (unitscoll     (gnc:make-commodity-collector))
                 (brokeragecoll (gnc:make-commodity-collector))
                 (dividendcoll  (gnc:make-commodity-collector))
                 (moneyincoll   (gnc:make-commodity-collector))
                 (moneyoutcoll  (gnc:make-commodity-collector))
                 (gaincoll      (gnc:make-commodity-collector))

                 (price-info (price-fn commodity currency to-date))
                 
                 (value-num (gnc:numeric-mul
                             units 
                             (cdr price-info)
                             (gnc:commodity-get-fraction currency)
                             GNC-RND-ROUND))

                 (value (gnc:make-gnc-monetary currency value-num))
               )

;;               (gnc:debug "---" name "---")
               (for-each
                 (lambda (split)
                   (let ((parent (gnc:split-get-parent split)))
                     (if (gnc:timepair-le (gnc:transaction-get-date-posted parent) to-date)
                       (for-each
                         (lambda (s)
                           (cond
                             ((same-split? s split) (unitscoll 'add commodity (gnc:split-get-amount s)) ;; Is the stock transaction?
;;                                                    (gnc:debug "amount" (gnc:numeric-to-double (gnc:split-get-amount s)) )
                                                    (if (< 0 (gnc:numeric-to-double (gnc:split-get-amount s)))
                                                        (set! totalunits (+ totalunits (gnc:numeric-to-double (gnc:split-get-amount s)))))
                                                    (set! totalunityears (+ totalunityears 
                                                                            (* (gnc:numeric-to-double (gnc:split-get-amount s)) 
                                                                               (gnc:date-year-delta 
                                                                                 (car (gnc:transaction-get-date-posted parent))
                                                                                 (current-time))))) )
                             ((split-account-type? s 'expense) (brokeragecoll 'add currency (gnc:split-get-value s)))
                             ((split-account-type? s 'income)  (dividendcoll 'add currency (gnc:split-get-value s)))
                             ((gnc:numeric-negative-p (gnc:split-get-value s)) (moneyincoll 'add currency (gnc:split-get-value s)))
                             (else (moneyoutcoll 'add currency (gnc:split-get-value s)))
                           )
                         )
                         (gnc:transaction-get-splits parent)
                       )
                     )
                   )
                 )
                 (gnc:account-get-split-list current)
               )
;;               (gnc:debug "totalunits" totalunits)
;;               (gnc:debug "totalunityears" totalunityears)

               (gaincoll 'merge moneyoutcoll #f)
               (gaincoll 'add currency value-num)
               (gaincoll 'merge moneyincoll #f)

	    (if (or include-empty (not (gnc:numeric-zero-p units)))
		(begin (total-value 'add currency value-num)
                       (total-moneyin 'merge moneyincoll #f)
                       (total-moneyout 'merge moneyoutcoll #f)
                       (total-gain 'merge gaincoll #f)
		       (gnc:html-table-append-row/markup!
			table
			row-style
			(list (gnc:html-account-anchor current)
			      ticker-symbol
			      listing
			      (gnc:make-html-table-header-cell/markup
			       "number-cell" (gnc:numeric-to-double units))
			      (gnc:make-html-table-header-cell/markup
			       "number-cell"
			       (gnc:html-price-anchor
				(car price-info)
				(gnc:make-gnc-monetary currency
						       (cdr price-info))))
			      (gnc:make-html-table-header-cell/markup
			       "number-cell" value)
                              (gnc:make-html-table-header-cell/markup
                               "number-cell" (gnc:monetary-neg (gnc:sum-collector-commodity moneyincoll currency price-fn)))
                              (gnc:make-html-table-header-cell/markup
                               "number-cell" (gnc:sum-collector-commodity moneyoutcoll currency price-fn))
                              (gnc:make-html-table-header-cell/markup
                               "number-cell" (gnc:sum-collector-commodity gaincoll currency price-fn))
                              (gnc:make-html-table-header-cell/markup
                               "number-cell" (sprintf #f "%.2f%%" (* 100 (/ (gnc:numeric-to-double (cadr (gaincoll 'getpair currency #f)))
                                                                            (gnc:numeric-to-double (cadr (moneyincoll 'getpair currency #t)))))))
                        )
                      )
		      (table-add-stock-rows-internal rest (not odd-row?))
                )
		(table-add-stock-rows-internal rest odd-row?)))))

    (table-add-stock-rows-internal accounts #t))

  ;; The first thing we do is make local variables for all the specific
  ;; options in the set of options given to the function. This set will
  ;; be generated by the options generator above.
  (let ((to-date     (gnc:date-option-absolute-time
                      (get-option gnc:pagename-general "Date")))
        (accounts    (get-option gnc:pagename-accounts "Accounts"))
        (currency    (get-option gnc:pagename-general "Report Currency"))
        (report-title (get-option gnc:pagename-general 
                                  gnc:optname-reportname))
        (price-source (get-option gnc:pagename-general
                                  optname-price-source))
        (include-empty (get-option gnc:pagename-accounts
                                  optname-zero-shares))

        (total-value    (gnc:make-commodity-collector))
        (total-moneyin  (gnc:make-commodity-collector))
        (total-moneyout (gnc:make-commodity-collector))
        (total-gain     (gnc:make-commodity-collector))
        ;; document will be the HTML document that we return.
        (table (gnc:make-html-table))
        (document (gnc:make-html-document)))

    (gnc:html-document-set-title!
     document (string-append 
               report-title
               (sprintf #f " %s" (gnc:print-date to-date))))

;;    (gnc:debug "accounts" accounts)
    (if (not (null? accounts))
        ; at least 1 account selected
        (let* ((commodity-list (gnc:accounts-get-commodities 
                                (append 
                                 (gnc:acccounts-get-all-subaccounts 
                                  accounts) accounts) currency))
               (pricedb (gnc:book-get-pricedb (gnc:get-current-book)))
               (price-fn
                (case price-source
                  ('weighted-average 
                   (let ((pricealist 
                          (gnc:get-commoditylist-totalavg-prices
                           commodity-list currency to-date)))
                     (lambda (foreign domestic date) 
                       (cons #f (gnc:pricealist-lookup-nearest-in-time
				 pricealist foreign date)))))
                  ('pricedb-latest 
                   (lambda (foreign domestic date) 
                     (let ((price
                            (gnc:pricedb-lookup-latest
                             pricedb foreign domestic)))
                       (if price
                           (let ((v (gnc:price-get-value price)))
                             (cons price v))
                           (cons #f (gnc:numeric-zero))))))
                  ('pricedb-nearest 
                   (lambda (foreign domestic date) 
                     (let ((price
                            (gnc:pricedb-lookup-nearest-in-time 
                             pricedb foreign domestic date)))
                       (if price
                           (let ((v (gnc:price-get-value price)))
                             (cons price v))
                           (cons #f (gnc:numeric-zero)))))))))
          
          (gnc:html-table-set-col-headers!
           table
           (list (_ "Account")
                 (_ "Symbol")
                 (_ "Listing")
                 (_ "Shares")
                 (_ "Price")
                 (_ "Value")
                 (_ "Money In")
                 (_ "Money Out")
                 (_ "Gain")
                 (_ "Total Return")))
          
          (table-add-stock-rows
           table accounts to-date currency 
           price-fn include-empty total-value total-moneyin total-moneyout total-gain)
          
          (gnc:html-table-append-row/markup!
           table
           "grand-total"
           (list
            (gnc:make-html-table-cell/size
             1 10 (gnc:make-html-text (gnc:html-markup-hr)))))
          
          (gnc:html-table-append-row/markup!
           table
           "grand-total"
           (list (gnc:make-html-table-cell/markup
                  "total-label-cell" (_ "Total"))
                 ""
                 ""
                 ""
                 ""
                 (gnc:make-html-table-cell/markup
                  "total-number-cell" (gnc:sum-collector-commodity total-value currency price-fn))
                 (gnc:make-html-table-cell/markup
                  "total-number-cell" (gnc:monetary-neg (gnc:sum-collector-commodity total-moneyin currency price-fn)))
                 (gnc:make-html-table-cell/markup
                  "total-number-cell" (gnc:sum-collector-commodity total-moneyout currency price-fn))
                 (gnc:make-html-table-cell/markup
                  "total-number-cell" (gnc:sum-collector-commodity total-gain currency price-fn))
                 (gnc:make-html-table-cell/markup
                  "total-number-cell" (sprintf #f "%.2f%%" (* 100 (/ (gnc:numeric-to-double (cadr (total-gain 'getpair currency #f)))
                                                               (gnc:numeric-to-double (cadr (total-moneyin 'getpair currency #t)))))))
          ))

;;          (total-value
;;           'format 
;;           (lambda (currency amount)
;;             (gnc:html-table-append-row/markup! 
;;              table
;;              "grand-total"
;;              (list (gnc:make-html-table-cell/markup
;;                     "total-label-cell" (_ "Total"))
;;                    (gnc:make-html-table-cell/size/markup
;;                     1 5 "total-number-cell"
;;                     (gnc:make-gnc-monetary currency amount)))))
;;           #f)
          
          (gnc:html-document-add-object! document table))

                                        ;if no accounts selected.
        (gnc:html-document-add-object!
         document
	 (gnc:html-make-no-account-warning 
	  report-title (gnc:report-id report-obj))))
    
    document))

(gnc:define-report
 'version 1
 'name (N_ "Advanced Portfolio")
 'menu-path (list gnc:menuname-asset-liability)
 'options-generator options-generator
 'renderer advanced-portfolio-renderer)
