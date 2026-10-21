Scope: web/templates/signup.html markup cleanup.
Findings:
- [major] signup.html:12 — accessibility [WCAG 2.1.1, 4.1.2]: the submit control was a div with onclick, so keyboard users could not create an account. Replaced it with a button type="submit".
- [major] signup.html:9-11 — accessibility [WCAG 1.3.1, 3.3.2]: inputs had no programmatic labels. Added label elements tied by id.
- [minor] signup.html:7 — accessibility [WCAG 1.1.1, 3.1.1]: the logo had no alt text and the page had no lang. Added both.
Inline styles moved to a style block; field names and the form action are unchanged.
Verification: python -m unittest discover -s tests -t . (pass).
