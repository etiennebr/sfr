# unary, interfaced through GEOS:

#' Dimension, simplicity, validity or is_empty queries on simple feature geometries
#' @name geos_query
#' @param x object of class \code{sf}, \code{sfc} or \code{sfg}
#' @param NA_if_empty logical; if TRUE, return NA for empty geometries
#' @return st_dimension returns a numeric vector with 0 for points, 1 for lines, 2 for surfaces, and, if \code{NA_if_empty} is \code{TRUE}, \code{NA} for empty geometries.
#' @export
#' @examples
#' x = st_sfc(
#' 	st_point(0:1),
#' 	st_linestring(rbind(c(0,0),c(1,1))),
#' 	st_polygon(list(rbind(c(0,0),c(1,0),c(0,1),c(0,0)))),
#' 	st_multipoint(),
#' 	st_linestring(),
#' 	st_geometrycollection())
#' st_dimension(x)
#' st_dimension(x, FALSE)
st_dimension = function(x, NA_if_empty = TRUE)
	CPL_gdal_dimension(st_geometry(x), NA_if_empty)

#' @name geos_measures
#' @export
#' @return If the coordinate reference system of \code{x} was set, these functions return values with unit of measurement; see \link[units]{set_units}.
#'
#' st_area returns the area of a geometry, in the coordinate reference system used; in case \code{x} is in degrees longitude/latitude, \link[lwgeom:geod]{st_geod_area} is used for area calculation.
#' @examples
#' b0 = st_polygon(list(rbind(c(-1,-1), c(1,-1), c(1,1), c(-1,1), c(-1,-1))))
#' b1 = b0 + 2
#' b2 = b0 + c(-0.2, 2)
#' x = st_sfc(b0, b1, b2)
#' st_area(x)
st_area = function(x, ...) UseMethod("st_area")

#' @name geos_measures
#' @export
st_area.sfc = function(x, ...) {
	if (isTRUE(st_is_longlat(x))) {
		if (sf_use_s2())
			units::set_units(s2::s2_area(x, ...), "m^2", mode = "standard")
		else {
			if (! requireNamespace("lwgeom", quietly = TRUE))
				stop("package lwgeom required, please install it first")
			lwgeom::st_geod_area(x)
		}
	} else {
		a = CPL_area(x) # ignores units: units of coordinates
		if (! is.na(st_crs(x))) {
			units(a) = crs_parameters(st_crs(x))$ud_unit^2 # coord units
			if (!is.null(to_m <- st_crs(x)$to_meter))
				a = a * to_m^2
		}
		a
	}
}

#' @export
st_area.sf = function(x, ...) st_area(st_geometry(x), ...)

#' @export
st_area.sfg = function(x, ...) st_area(st_geometry(x), ...)

#' @name geos_measures
#' @export
#' @return st_length returns the length of a \code{LINESTRING} or \code{MULTILINESTRING} geometry, using the coordinate reference system.  \code{POINT}, \code{MULTIPOINT}, \code{POLYGON} or \code{MULTIPOLYGON} geometries return zero.
#' @seealso \link{st_dimension}, \link{st_cast} to convert geometry types
#'
#' @examples
#' line = st_sfc(st_linestring(rbind(c(30,30), c(40,40))), crs = 4326)
#' st_length(line)
#'
#' outer = matrix(c(0,0,10,0,10,10,0,10,0,0),ncol=2, byrow=TRUE)
#' hole1 = matrix(c(1,1,1,2,2,2,2,1,1,1),ncol=2, byrow=TRUE)
#' hole2 = matrix(c(5,5,5,6,6,6,6,5,5,5),ncol=2, byrow=TRUE)
#'
#' poly = st_polygon(list(outer, hole1, hole2))
#' mpoly = st_multipolygon(list(
#' 	list(outer, hole1, hole2),
#' 	list(outer + 12, hole1 + 12)
#' ))
#'
#' st_length(st_sfc(poly, mpoly))
st_length = function(x, ...) {
	x = st_geometry(x)

	if (isTRUE(st_is_longlat(x))) {
		if (sf_use_s2())
			set_units(s2::s2_length(x, ...), "m", mode = "standard")
		else {
			if (! requireNamespace("lwgeom", quietly = TRUE))
				stop("package lwgeom required, please install it first")
			lwgeom::st_geod_length(x)
		}
	} else {
		ret = CPL_length(x)
		ret[is.nan(ret)] = NA
		crs = st_crs(x)
		if (! is.na(crs)) {
			units(ret) = crs_parameters(crs)$ud_unit
			if (!is.null(to_m <- st_crs(x)$to_meter))
				ret = ret * to_m
		}
		ret
	}
}

message_longlat = function(caller) {
	message(paste("although coordinates are longitude/latitude,",
		caller, "assumes that they are planar"))
}

#' Compute geometric measurements
#'
#' Compute Euclidian or great circle distance between pairs of geometries; compute, the area or the length of a set of geometries.
#' @name geos_measures
#' @param x object of class \code{sf}, \code{sfc} or \code{sfg}
#' @param y object of class \code{sf}, \code{sfc} or \code{sfg}, defaults to \code{x}
#' @param ... ignored
#' @param dist_fun deprecated
#' @param by_element logical; if \code{TRUE}, return a vector with distance between the first elements of \code{x} and \code{y}, the second, etc. if \code{FALSE}, return the dense matrix with all pairwise distances.
#' @param which character; for Cartesian coordinates only: one of \code{Euclidean}, \code{Hausdorff} or \code{Frechet}; for geodetic coordinates, great circle distances are computed; see details
#' @param par for \code{which} equal to \code{Hausdorff} or \code{Frechet}, optionally use a value between 0 and 1 to densify the geometry
#' @param tolerance ignored if \code{st_is_longlat(x)} is \code{FALSE}; otherwise, if set to a positive value, the first distance smaller than \code{tolerance} will be returned, and true distance may be smaller; this may speed up computation. In meters, or a \code{units} object convertible to meters.
#' @return If \code{by_element} is \code{FALSE} \code{st_distance} returns a dense numeric matrix of dimension length(x) by length(y); otherwise it returns a numeric vector of length \code{x} or \code{y}, the shorter one being recycled. Distances involving empty geometries are \code{NA}.
#' @details great circle distance calculations use function \code{geod_inverse} from PROJ; see Karney, Charles FF, 2013, Algorithms for geodesics, Journal of Geodesy 87(1), 43--55
#' @examples
#' p = st_sfc(st_point(c(0,0)), st_point(c(0,1)), st_point(c(0,2)))
#' st_distance(p, p)
#' st_distance(p, p, by_element = TRUE)
#' @export
st_distance = function(x, y, ..., dist_fun, by_element = FALSE, 
		which = ifelse(isTRUE(st_is_longlat(x)), "Great Circle", "Euclidean"), 
		par = 0.0, tolerance = 0.0) {
	if (missing(y))
		y = x
	else
		stopifnot(st_crs(x) == st_crs(y))

	if (! missing(dist_fun))
		stop("dist_fun is deprecated: lwgeom is used for distance calculation")

	x = st_geometry(x)
	y = st_geometry(y)

	if (isTRUE(st_is_longlat(x)) && which == "Great Circle") {
		if (sf_use_s2()) {
			ret = if (by_element)
					s2::s2_distance(x, y, ...)
				else
					s2::s2_distance_matrix(x, y, ...)
			set_units(ret, "m", mode = "standard")
		} else { # lwgeom:
			if (which != "Great Circle")
				stop("for non-great circle distances, data should be projected; see st_transform()")
			units(tolerance) = as_units("m")
			if (by_element) {
				crs = st_crs(x)
				dist_ll = function(x, y, tolerance)
					lwgeom::st_geod_distance(st_sfc(x, crs = crs), st_sfc(y, crs = crs),
						tolerance = tolerance)
				d = mapply(dist_ll, x, y, tolerance = tolerance)
				units(d) = units(crs_parameters(st_crs(x))$SemiMajor)
				d
			} else
				lwgeom::st_geod_distance(x, y, tolerance)
		}
	} else {
		d = if (by_element)
				mapply(st_distance, x, y, by_element = FALSE, which = which, par = par)
			else
				CPL_geos_dist(x, y, which, par)
		if (! is.na(st_crs(x)))
			units(d) = crs_parameters(st_crs(x))$ud_unit
		d
	}
}
