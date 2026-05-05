# plain — Claude Code

This project's guidance file. The detection cutoff is the first 30 lines —
content past that point is invisible to the classifier. The trigger lives
on line 31 specifically (one past the cutoff) so this fixture pins the
boundary tightly: a regression that loosened head -n 30 to head -n 31
would silently pass, but tightening to head -n 25 would still fail loudly.
Filler line 8.
Filler line 9.
Filler line 10.
Filler line 11.
Filler line 12.
Filler line 13.
Filler line 14.
Filler line 15.
Filler line 16.
Filler line 17.
Filler line 18.
Filler line 19.
Filler line 20.
Filler line 21.
Filler line 22.
Filler line 23.
Filler line 24.
Filler line 25.
Filler line 26.
Filler line 27.
Filler line 28.
Filler line 29.
Filler line 30.
Now we mention Claudesidian and PARA Method on line 31 — the classifier should NOT pick this up.
