"""Declared column layouts for the register books this service reads.

This module is *data*, not detection logic. Nothing here looks at an image.

Why a declared layout at all, when every other stage of this pipeline insists
on measuring the page rather than assuming things about it: a printed register
sub-divides some of its own columns, and those sub-dividers are printed rules
identical in character to the genuine column boundaries. Measured directly on
the sample photographs, the "L or ILL (Check space)" column carries an internal
divider between its two check cells, and both "NAME OF PARENTS" and "SPONSORS"
are ruled into two name sub-columns. A detector that counts vertical rules
therefore cannot tell a logical column boundary from a sub-divider — not
because it is badly tuned, but because on the page they are the same mark. A
sweep of a hundred kernel/merge-gap combinations over six page-halves never
found the right column count on more than three of them.

What *is* knowable without inspecting the photograph is that this is one
printed book with one fixed ruling. So the column proportions are declared
here, once, and fitted to wherever the table turns out to be on each
photograph (see ``table.fit_column_template``). The page still decides the
table's position and size; only the *proportions within* the table are
declared. How many of the fitted boundaries land on an independently detected
vertical rule is measured every time and reported as a confidence signal, so a
declaration that stops matching the page is caught rather than trusted.

Adding support for another register book — a marriage or burial register with
a different ruling — is a matter of adding another ``ColumnTemplate`` constant
here and passing it in. No detection code changes.

The column keys are the field keys the rest of the system uses, so a fitted
grid can be handed downstream without a translation table in between.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class ColumnTemplate:
    """One page's declared column ruling.

    ``boundaries`` are fractions of the *table's own* horizontal extent, never
    of the page image: 0.0 is the table's left border and 1.0 its right
    border. This distinction is the whole point. After a spread is split into
    two page crops, each crop still contains whatever the book was resting on
    beyond the paper's edge, and how much varies with how the photograph was
    framed — measured across the sample photographs, the left page's table
    starts anywhere from 34% to 37% of the way across its own crop. Fractions
    of the page image would therefore be a different (and wrong) layout for
    every photograph; fractions of the table are the same layout every time,
    because they describe the printed book.

    ``columns`` names the cells *between* consecutive boundaries, so there is
    always exactly one more boundary than there are columns.
    """

    name: str
    columns: tuple[str, ...]
    boundaries: tuple[float, ...]

    def __post_init__(self) -> None:
        if len(self.boundaries) != len(self.columns) + 1:
            raise ValueError(
                f"{self.name}: {len(self.columns)} columns need "
                f"{len(self.columns) + 1} boundaries, got {len(self.boundaries)}"
            )
        if self.boundaries[0] != 0.0 or self.boundaries[-1] != 1.0:
            raise ValueError(
                f"{self.name}: boundaries must run from 0.0 (the table's left "
                f"border) to 1.0 (its right border), got "
                f"{self.boundaries[0]}..{self.boundaries[-1]}"
            )
        if any(b >= c for b, c in zip(self.boundaries, self.boundaries[1:])):
            raise ValueError(f"{self.name}: boundaries must strictly increase")

    @property
    def column_count(self) -> int:
        return len(self.columns)


@dataclass(frozen=True)
class SpreadColumnTemplate:
    """The two page layouts of one open register book.

    A spread is photographed as a single image of two facing pages, and the
    two pages carry different halves of one continuous ruled table — so they
    have different column rulings and must be given different templates. This
    pairs them so a caller cannot accidentally fit the left page's ruling to
    the right page.

    ``data_row_count`` is the number of *data* rows the printed book is ruled
    for (excluding the column-header band). It is declared, not detected, for
    the same reason the column proportions are: it is a fixed property of the
    printed form, and on a faded or angled photograph the lower row rules can
    drop out of the image entirely — there is nothing left to detect. See
    ``table._lay_declared_rows``.
    """

    name: str
    left: ColumnTemplate
    right: ColumnTemplate
    data_row_count: int


# --- The baptismal register this service was built for -----------------------
#
# Proportions measured from the printed header bands of the sample
# photographs. Each was read independently on all three photographs and the
# three readings agreed to within 0.01 of the table width (about 12px at the
# sampled resolution), which is the resolution of the reading method itself —
# so these are the register's ruling, not one photograph's accident.
#
# The declared boundaries are the *logical* column edges: the ones that
# separate one heading from the next. The internal sub-dividers described in
# this module's docstring are deliberately absent, which is exactly what a
# rule-counting detector cannot achieve on its own.

BAPTISMAL_LEFT = ColumnTemplate(
    name="baptismal_register_left_page",
    columns=(
        "no",
        "child_name",
        "place_and_birth_date",
        "l_or_ill",
        "parents",
    ),
    boundaries=(
        0.000,  # table's left border
        0.066,  # NO. | NAME OF CHILD
        0.311,  # NAME OF CHILD | PLACE & DATE OF BIRTH
        0.607,  # PLACE & DATE OF BIRTH | L or ILL (Check space)
        0.689,  # L or ILL | NAME OF PARENTS (Mother's Maiden Name)
        1.000,  # table's right border
    ),
)

BAPTISMAL_RIGHT = ColumnTemplate(
    name="baptismal_register_right_page",
    columns=(
        "residents_of",
        "baptism_date",
        "minister",
        "sponsors",
        "observations",
    ),
    boundaries=(
        0.000,  # table's left border
        0.223,  # RESIDENTS OF | DATE OF BAPTISM
        0.364,  # DATE OF BAPTISM | MINISTER
        0.612,  # MINISTER | SPONSORS
        0.868,  # SPONSORS | OBSERVATIONS
        1.000,  # table's right border
    ),
)

BAPTISMAL_REGISTER = SpreadColumnTemplate(
    name="baptismal_register",
    left=BAPTISMAL_LEFT,
    right=BAPTISMAL_RIGHT,
    data_row_count=24,
)
