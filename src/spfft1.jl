#= src/spfft1.jl
=#

immutable cSpFFTPlan1{T<:SpFFTComplex,K}
  X::Matrix{T}
  F::FFTPlan{T,K}
  w::Vector{T}
  col::Vector{Int}
  p::Vector{Int}
end

spfft_size(P::cSpFFTPlan1) = (size(P.X)..., length(P.w))

function spfft_blkdiv(n::Integer, k::Integer)
  l = k
  while n % l > 0
    l -= 1
  end
  m = div(n, l)
  l, m
end

for (fcn, K) in ((:fft, FORWARD), (:bfft, BACKWARD))
  sf  = Symbol("sp", fcn)
  psf = Symbol("plan_", sf)
  pf  = Symbol("plan_", fcn, "!")
  f2s = Symbol(sf, "_f2s!")
  s2f = Symbol(sf, "_s2f!")
  NB  = 128
  @eval begin
    function $psf{T<:SpFFTComplex,Ti<:Integer}(
        ::Type{T}, n::Integer, idx::AbstractVector{Ti}; args...)
      n > 0 || throw(ArgumentError("n"))
      k = length(idx)
      @inbounds for i = 1:k
        (1 <= idx[i] <= n) || throw(DomainError())
      end
      l, m = spfft_blkdiv(n, k)
      X = Array(T, l, m)
      F = $pf(X, 1; args...)
      wm = exp(2im*$K*pi/m)
      wn = exp(2im*$K*pi/n)
      w = Array(T, k)
      col = Array(Int, k)
      @inbounds for i = 1:k
        rowm1  = fld(idx[i]-1, l)
        col[i] = idx[i] - rowm1*l
        w[i] = wm^rowm1 * wn^(col[i]-1)
      end
      cSpFFTPlan1{T,$K}(X, F, w, col, sortperm(col))
    end

    function $f2s{T<:SpFFTComplex,K}(
        y::AbstractVector{T}, P::cSpFFTPlan1{T,K}, x::AbstractVector{T};
        nb::Integer=$NB)
      l, m, k = spfft_size(P)
      length(x) == l*m || throw(DimensionMismatch)
      length(y) == k   || throw(DimensionMismatch)
      transpose!(P.X, reshape(x,(m,l)))
      P.F*P.X
      y[:] = 0
      nb = min(nb, k)
      s = Array(T, nb)
      idx = 0
      while idx < k
        s[:] = 1
        nbi = min(nb, k-idx)
        @inbounds for j = 1:m
          for i = 1:nbi
            ii = idx + i
            p = P.p[ii]
            y[ii] += s[i]*P.X[P.col[p],j]
            s[i] *= P.w[p]
          end
        end
        idx += nbi
      end
      ipermute!(y, P.p)
    end

    function $s2f{T<:SpFFTComplex,K}(
        y::AbstractVector{T}, P::cSpFFTPlan1{T,K}, x::AbstractVector{T};
        nb::Integer=$NB)
      l, m, k = spfft_size(P)
      length(x) == k   || throw(DimensionMismatch)
      length(y) == l*m || throw(DimensionMismatch)
      P.X[:] = 0
      nb = min(nb, k)
      s = Array(T, nb)
      idx = 0
      xp = x[P.p]
      while idx < k
        s[:] = 1
        nbi = min(nb, k-idx)
        @inbounds for j = 1:m
          for i = 1:nbi
            ii = idx + i
            p = P.p[ii]
            P.X[P.col[p],j] += s[i]*xp[ii]
            s[i] *= P.w[p]
          end
        end
        idx += nbi
      end
      P.F*P.X
      transpose!(reshape(y,(m,l)), P.X)
      y
    end
  end
end