export type Line = [Point, Point, Point, Point] // start, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, end

export type BezierCurve = [Point, Point, Point, Point] // start, control1, control2, end

// Union type for path segments - now both have same structure
export type PathSegment = Line | BezierCurve
