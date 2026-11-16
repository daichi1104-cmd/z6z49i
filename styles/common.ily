\version "2.24.0"
#(set-global-staff-size 18)
\paper {
  indent = 0
  line-width = 108\mm
  ragged-right = ##f
  ragged-last = ##f
  print-page-number = ##f
  oddFooterMarkup = ##f
  evenFooterMarkup = ##f
}
\header { tagline = ##f }
\layout {
  \context { \Score \override StringNumber.font-size = #-3 }
  \context { \ChordNames \override ChordName.font-size = #0 }
}
