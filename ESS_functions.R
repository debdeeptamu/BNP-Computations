#####################################################################
########## Function for MCMC samples using ESS and WC algo ##########
#####################################################################

library(MASS); library(FastGP)

### Function for drawing posterior samples using ESS with fixed hyperparameters:

########### For monotone functions estimation ##############
mon.inc.ESS=function(y,x,nu,N,l,eta,mcmc,brn,thin,tau.in,sig.in,xi0.in,xi.in,xi0.fix,
                 tau.fix,sig.fix,xi.fix,sseed,verbose,return.plot,return.traplot){
  # y:Response variable; x: vector to form design matrix \Psi (n X N+1)
  # N: (N+1) is the number of knots
  # nu:smoothness parameter of Matern; l:length-scale parameter of Matern
  # eta:parameter of the approximation function of the indicator functions
  # mcmc, brn, thin : mcmc samples, burning and thinning for MCMC
  # tau.in, sig.in, xi0.in, xi.in : initial values (supplied by user or use the default values)
  # xi0.fix,tau.fix,sig.fix,xi.fix : if fixed values of the parameters are to use
  # verbose : logical; if TRUE, prints currnet status; default is TRUE
  # return.plot : logical; if true a plot of estimate with 95% CI is returned; default is TRUE
  # return.traplot : logical; if true traceplots are returned; default is TRUE
  
  # OUTPUT: Posterior samples on xi,xi0,tau,sig and fhat with posterior mean, 95% CI of fhat
  ptm=proc.time()
  
  if(length(y)!=length(x))
    stop("y and x should be of same length!")
  n=length(y)
  if(missing(N))
    N = ceiling(n/2) - 1
  int_length=1/N
  my_knots=seq(0,1,by=int_length)
  X=des.mat1(x,my_knots,int_length)
  
  if(missing(nu))
    stop("nu needs to be supplied")
  if(nu==0)
    stop("nu cannot be zero")
  if(!missing(l) && l==0)
    stop("l cannot be zero")
  
  if(missing(return.plot))
    return.plot=TRUE
  if(missing(return.traplot))
    return.traplot=TRUE
  
  if(!missing(sseed))
    set.seed(sseed)
  if(missing(sseed))
    set.seed(Sys.Date())
  
  if(missing(verbose))
    verbose=TRUE
  
  if(missing(l))
    l=l_est(nu,c(my_knots[1],my_knots[length(my_knots)]),0.05)
  
  # prior covariance K:
  K = covmat(my_knots,nu,l)
  # prior precision:
  K_inv = tinv(K)
  
  if(missing(eta))
    eta=50
  if(missing(mcmc))
    mcmc=5000
  if(missing(brn))
    brn=1000
  if(missing(thin))
    thin=1
  em=mcmc+brn
  ef=mcmc/thin
  
  if(!missing(tau.fix))
    tau.in=tau.fix
  if(!missing(sig.fix))
    sig.in=sig.fix
  if(!missing(xi0.fix))
    xi0.in=xi0.fix
  if(!missing(xi.fix))
    xi.in=xi.fix
  
  if(missing(tau.fix) && missing(tau.in))
    tau.in=1
  if(missing(sig.fix) && missing(sig.in))
    sig.in=1
  if(missing(xi0.fix) && missing(xi0.in))
    xi0.in=0
  if(missing(xi.fix) && missing(xi.in))
    xi.in=pmax(0,mvrnorm(1,rep(0,N+1),K))
  
  tau=tau.in
  sig=sig.in
  xi0=xi0.in
  xi_in=xi.in
  
  xi_sam=matrix(0,N+1,ef)
  xi0_sam=rep(0,ef)
  tau_sam=rep(0,ef)
  sig_sam=rep(0,ef)
  fhat_sam=matrix(0,n,ef)
  
  if(verbose)
    print("MCMC sample draws:")
  
  for(i in 1:em){
    # sampling Xi:
    if(missing(xi.fix)){
      y_tilde = y - xi0
      nu.ess = as.vector(samp.WC(my_knots,nu,l,tau))
      xi_out = ESS(xi_in,nu.ess,y_tilde,X,sig,eta)
      xi_out = sapply(xi_out,function(z) return(max(0,z)))
    }else{
      xi_out=xi_in
    }
    
    # sampling xi_0:
    Xxi = as.vector(X %*% xi_out)
    y_star = y - Xxi
    if(missing(xi0.fix))
      xi0 = rnorm(1,mean(y_star),sqrt(sig/n))
    
    # sampling \sigma^2:
    y0 = y_star - xi0
    if(missing(sig.fix))
      sig = 1/rgamma(1,shape = n/2,rate = sum(y0^2)/2)
    
    # sampling \tau^2:
    if(missing(tau.fix))
      tau = 1/rgamma(1, shape = (N+1)/2, rate = (t(xi_out)%*%K_inv%*%xi_out)/2)
    
    # storing MCMC samples:
    if(i > brn && i%%thin == 0){
      xi_sam[,(i-brn)/thin]=xi_out
      xi0_sam[(i-brn)/thin]=xi0
      sig_sam[(i-brn)/thin]=sig
      tau_sam[(i-brn)/thin]=tau
      fhat_sam[,(i-brn)/thin]=xi0 + Xxi
    }
    
    if(i%%1000==0 && verbose){
      print(i)
    }
    
    # renewing the intial value:
    xi_in = xi_out
  }
  
  if(return.traplot){
    library(mcmcplots)
    mx=min(N+1,25)
    xi_mat=matrix(xi_sam[1:mx,],nrow = mx,
                  dimnames = list(c(paste("xi[",1:mx,"]",sep = "")),NULL))
    traplot(t(xi_mat))
    par(mfrow=c(1,1))
    traplot(as.mcmc(xi0_sam),main=expression(paste(xi[0])))
    traplot(as.mcmc(sig_sam),main=expression(paste(sigma^2)))
    traplot(as.mcmc(tau_sam),main=expression(paste(tau^2)))
  }
  
  fmean=rowMeans(fhat_sam)
  fsort=fhat_sam
  for(i in 1:nrow(fhat_sam)){
    fsort[i,]=sort(fhat_sam[i,])
  }
  f_low=fsort[,ef*0.025]
  f_upp=fsort[,ef*0.975]
  ub=max(f_low,f_upp,fmean)
  lb=min(f_low,f_upp,fmean)
  
  if(return.plot){
    par(mfrow=c(1,1))
    plot(x,fmean,type="l",lwd=2,main="Black: Estimate, Blue: 95% CI",ylim=c(lb,ub))
    lines(x,f_low,lwd=2,lty=2,col="blue")
    lines(x,f_upp,lwd=2,lty=2,col="blue")
  }
  
  tm=proc.time()-ptm
  return(list("time"=tm,"xi_sam"=xi_sam,"xi0_sam"=xi0_sam,"sig_sam"=sig_sam,"tau_sam"=tau_sam,
              "fhat_sam"=fhat_sam,"fmean"=fmean,"f_low"=f_low,"f_upp"=f_upp))
}



mon.dec.ESS=function(y,x,nu,N,l,eta,mcmc,brn,thin,tau.in,sig.in,xi0.in,xi.in,xi0.fix,
                     tau.fix,sig.fix,xi.fix,sseed,verbose,return.plot,return.traplot){
  # y:Response variable; x: vector to form design matrix \Psi (n X N+1)
  # N: (N+1) is the number of knots
  # nu:smoothness parameter of Matern; l:length-scale parameter of Matern
  # eta:parameter of the approximation function of the indicator functions
  # mcmc, brn, thin : mcmc samples, burning and thinning for MCMC
  # tau.in, sig.in, xi0.in, xi.in : initial values (supplied by user or use the default values)
  # xi0.fix, tau.fix, sig.fix, xi.fix : if fixed values are to use
  # verbose : logical; if TRUE, prints currnet status; default is TRUE
  # return.plot : logical; if true a plot of estimate with 95% CI is returned; default is TRUE
  # return.traplot : logical; if true traceplots are returned; default is TRUE
  
  # OUTPUT: Posterior samples on xi,xi0,tau,sig and fhat with posterior mean, 95% CI of fhat
  ptm=proc.time()
  
  if(length(y)!=length(x))
    stop("y and x should be of same length!")
  n=length(y)
  if(missing(N))
    N = ceiling(n/2) - 1
  int_length=1/N
  my_knots=seq(0,1,by=int_length)
  X=des.mat1(x,my_knots,int_length)
  
  if(missing(nu))
    stop("nu needs to be supplied")
  if(nu==0)
    stop("nu cannot be zero")
  if(!missing(l) && l==0)
    stop("l cannot be zero")
  
  if(missing(return.plot))
    return.plot=TRUE
  if(missing(return.traplot))
    return.traplot=TRUE
  
  if(!missing(sseed))
    set.seed(sseed)
  if(missing(sseed))
    set.seed(Sys.Date())
  
  if(missing(verbose))
    verbose=TRUE
  
  if(missing(l))
    l=l_est(nu,c(my_knots[1],my_knots[length(my_knots)]),0.05)

  # prior covariance K:
  K = covmat(my_knots,nu,l)
  # prior precision:
  K_inv = solve(K)
  
  if(missing(eta))
    eta=50
  if(missing(mcmc))
    mcmc=5000
  if(missing(brn))
    brn=1000
  if(missing(thin))
    thin=1
  em=mcmc+brn
  ef=mcmc/thin
  
  if(!missing(tau.fix))
    tau.in=tau.fix
  if(!missing(sig.fix))
    sig.in=sig.fix
  if(!missing(xi0.fix))
    xi0.in=xi0.fix
  if(!missing(xi.fix))
    xi.in=xi.fix
  
  if(missing(tau.fix) && missing(tau.in))
    tau.in=1
  if(missing(sig.fix) && missing(sig.in))
    sig.in=1
  if(missing(xi0.fix) && missing(xi0.in))
    xi0.in=0
  if(missing(xi.fix) && missing(xi.in))
    xi.in=pmin(0,mvrnorm(1,rep(0,N+1),K))
  
  tau=tau.in
  sig=sig.in
  xi0=xi0.in
  xi_in=xi.in
  
  xi_sam=matrix(0,N+1,ef)
  xi0_sam=rep(0,ef)
  tau_sam=rep(0,ef)
  sig_sam=rep(0,ef)
  fhat_sam=matrix(0,n,ef)
  
  if(verbose)
    print("MCMC sample draws:")
  
  for(i in 1:em){
    
    if(missing(xi.fix)){
      # sampling Xi:
      y_tilde = y - xi0
      nu.ess = as.vector(samp.WC(my_knots,nu,l,tau))
      xi_out = ESS.dec(xi_in,nu.ess,y_tilde,X,sig,eta)
      xi_out = sapply(xi_out,function(z) return(min(0,z)))
    }else{
      xi_out = xi_in
    }
    
    # sampling xi_0:
    Xxi = as.vector(X %*% xi_out)
    y_star = y - Xxi
    if(missing(xi0.fix))
      xi0 = rnorm(1,mean(y_star),sqrt(sig/n))
    
    # sampling \sigma^2:
    y0 = y_star - xi0
    if(missing(sig.fix))
      sig = 1/rgamma(1,shape = n/2,rate = sum(y0^2)/2)
    
    # sampling \tau^2:
    if(missing(tau.fix))
      tau = 1/rgamma(1, shape = (N+1)/2, rate = (t(xi_out)%*%K_inv%*%xi_out)/2)
    
    # storing MCMC samples:
    if(i > brn && i%%thin == 0){
      xi_sam[,(i-brn)/thin]=xi_out
      xi0_sam[(i-brn)/thin]=xi0
      sig_sam[(i-brn)/thin]=sig
      tau_sam[(i-brn)/thin]=tau
      fhat_sam[,(i-brn)/thin]=xi0 + Xxi
    }
    
    if(i%%1000==0 && verbose){
      print(i)
    }
    
    # renewing the intial value:
    xi_in = xi_out
  }
  
  if(return.traplot){
    library(mcmcplots)
    mx=min(N+1,25)
    xi_mat=matrix(xi_sam[1:mx,],nrow = mx,
                  dimnames = list(c(paste("xi[",1:mx,"]",sep = "")),NULL))
    traplot(t(xi_mat))
    par(mfrow=c(1,1))
    traplot(as.mcmc(xi0_sam),main=expression(paste(xi[0])))
    traplot(as.mcmc(sig_sam),main=expression(paste(sigma^2)))
    traplot(as.mcmc(tau_sam),main=expression(paste(tau^2)))
  }
  
  fmean=rowMeans(fhat_sam)
  fsort=fhat_sam
  for(i in 1:nrow(fhat_sam)){
    fsort[i,]=sort(fhat_sam[i,])
  }
  f_low=fsort[,ef*0.025]
  f_upp=fsort[,ef*0.975]
  ub=max(f_low,f_upp,fmean)
  lb=min(f_low,f_upp,fmean)
  
  if(return.plot){
    par(mfrow=c(1,1))
    plot(x,fmean,type="l",lwd=2,main="Black: Estimate, Blue: 95% CI",ylim=c(lb,ub))
    lines(x,f_low,lwd=2,lty=2,col="blue")
    lines(x,f_upp,lwd=2,lty=2,col="blue")
  }
  
  tm=proc.time()-ptm
  return(list("time"=tm,"xi_sam"=xi_sam,"xi0_sam"=xi0_sam,"sig_sam"=sig_sam,"tau_sam"=tau_sam,
              "fhat_sam"=fhat_sam,"fmean"=fmean,"f_low"=f_low,"f_upp"=f_upp))
}



########### For convex functions estimation ##############
con.ESS=function(y,x,nu,N,l,eta,mcmc,brn,thin,tau.in,sig.in,xi0.in,xi1.in,xi.in,
                 xi0.fix,xi1.fix,tau.fix,sig.fix,xi.fix,sseed,
                 verbose,return.plot,return.traplot){
  # y:Response variable; x: vector to form design matrix \Psi (n X N+1)
  # N: (N+1) is the number of knots
  # nu:smoothness parameter of Matern; l:length-scale parameter of Matern
  # eta:parameter of the approximation function of the indicator functions
  # mcmc, brn, thin : mcmc samples, burning and thinning for MCMC
  # tau.in, sig.in, xi0.in, xi1.in, xi.in : initial values (supplied by user or use the default value)
  # xi0.fix, xi1.fix, tau.fix, sig.fix, xi.fix : if fixed values are to use
  # verbose : logical; if TRUE, prints currnet status; default is TRUE
  # return.plot : logical; if true a plot of estimate with 95% CI is returned; default is TRUE
  # return.traplot : logical; if true traceplots are returned; default is TRUE
  
  # OUTPUT: Posterior samples on xi,xi0,xi1,tau,sig and fhat with posterior mean, 95% CI of fhat
  ptm=proc.time()
  
  if(length(y)!=length(x))
    stop("y and x should be of same length!")
  n=length(y)
  if(missing(N))
    N = ceiling(n/2) - 1
  int_length=1/N
  my_knots=seq(0,1,by=int_length)
  X=des.mat2(x,my_knots,int_length)
  
  if(missing(nu))
    stop("nu needs to be supplied")
  if(nu==0)
    stop("nu cannot be zero")
  if(!missing(l) && l==0)
    stop("l cannot be zero")
  
  if(missing(return.plot))
    return.plot=TRUE
  if(missing(return.traplot))
    return.traplot=TRUE
  
  if(!missing(sseed))
    set.seed(sseed)
  if(missing(sseed))
    set.seed(Sys.Date())
  
  if(missing(verbose))
    verbose=TRUE
  
  if(missing(l))
    l=l_est(nu,c(my_knots[1],my_knots[length(my_knots)]),0.05)
  
  # prior covariance K:
  K = covmat(my_knots,nu,l)
  # prior precision:
  K_inv = tinv(K)
  
  if(missing(eta))
    eta=50
  if(missing(mcmc))
    mcmc=5000
  if(missing(brn))
    brn=1000
  if(missing(thin))
    thin=1
  em=mcmc+brn
  ef=mcmc/thin
  
  if(!missing(tau.fix))
    tau.in=tau.fix
  if(!missing(sig.fix))
    sig.in=sig.fix
  if(!missing(xi0.fix))
    xi0.in=xi0.fix
  if(!missing(xi1.fix))
    xi1.in=xi1.fix
  if(!missing(xi.fix))
    xi.in=xi.fix
  
  if(missing(tau.fix) && missing(tau.in))
    tau.in=1
  if(missing(sig.fix) && missing(sig.in))
    sig.in=1
  if(missing(xi0.fix) && missing(xi0.in))
    xi0.in=0
  if(missing(xi1.fix) && missing(xi1.in))
    xi1.in=0
  if(missing(xi.fix) && missing(xi.in))
    xi.in=pmax(0,mvrnorm(1,rep(0,N+1),K))
  
  tau=tau.in
  sig=sig.in
  xi0=xi0.in
  xi1=xi1.in
  xi_in=xi.in
  
  xi_sam=matrix(0,N+1,ef)
  xi0_sam=rep(0,ef)
  xi1_sam=rep(0,ef)
  tau_sam=rep(0,ef)
  sig_sam=rep(0,ef)
  fhat_sam=matrix(0,n,ef)
  
  if(verbose)
    print("MCMC sample draws:")
  
  for(i in 1:em){
    # sampling \Xi:
    if(missing(xi.fix)){
      y_tilde = y - xi0 - xi1*x
      nu.ess = as.vector(samp.WC(my_knots,nu,l,tau))
      xi_out = ESS(xi_in,nu.ess,y_tilde,X,sig,eta)
      xi_out = sapply(xi_out,function(z) return(max(0,z)))
    }else{
      xi_out = xi_in
    }
    
    # sampling \xi_0:
    Xxi = as.vector(X %*% xi_out)
    y_star = y - xi1*x - Xxi
    if(missing(xi0.fix))
      xi0 = rnorm(1,mean(y_star),sqrt(sig/n))
    
    # sampling \xi_1:
    y1 = y - xi0 - Xxi
    if(missing(xi1.fix))
      xi1 = rnorm(1,(sum(x*y1)/sum(x^2)),sqrt(sig/sum(x^2)))
    
    # sampling \sigma^2:
    y0 = y - xi0 - xi1*x - Xxi
    if(missing(sig.fix))
      sig = 1/rgamma(1,shape = n/2,rate = sum(y0^2)/2)
    
    # sampling \tau^2:
    if(missing(tau.fix))
      tau = 1/rgamma(1, shape = (N+1)/2, rate = (t(xi_out)%*%K_inv%*%xi_out)/2)
    
    # storing MCMC samples:
    if(i > brn && i%%thin == 0){
      xi_sam[,(i-brn)/thin]=xi_out
      xi0_sam[(i-brn)/thin]=xi0
      xi1_sam[(i-brn)/thin]=xi1
      sig_sam[(i-brn)/thin]=sig
      tau_sam[(i-brn)/thin]=tau
      fhat_sam[,(i-brn)/thin]=xi0 + xi1*x + Xxi
    }
    
    if(i%%1000==0 && verbose){
      print(i)
    }
    
    # renewing the intial value:
    xi_in = xi_out
  }
  
  if(return.traplot){
    library(mcmcplots)
    mx=min(N+1,25)
    xi_mat=matrix(xi_sam[1:mx,],nrow = mx,
                  dimnames = list(c(paste("xi[",1:mx,"]",sep = "")),NULL))
    traplot(t(xi_mat))
    par(mfrow=c(1,1))
    traplot(as.mcmc(xi0_sam),main=expression(paste(xi[0])))
    traplot(as.mcmc(xi1_sam),main=expression(paste(xi[1])))
    traplot(as.mcmc(sig_sam),main=expression(paste(sigma^2)))
    traplot(as.mcmc(tau_sam),main=expression(paste(tau^2)))
  }
  
  fmean=rowMeans(fhat_sam)
  fsort=fhat_sam
  for(i in 1:nrow(fhat_sam)){
    fsort[i,]=sort(fhat_sam[i,])
  }
  f_low=fsort[,ef*0.025]
  f_upp=fsort[,ef*0.975]
  ub=max(f_low,f_upp,fmean)
  lb=min(f_low,f_upp,fmean)
  
  if(return.plot){
    par(mfrow=c(1,1))
    plot(x,fmean,type="l",lwd=2,main="Black: Estimate, Blue: 95% CI",ylim=c(lb,ub))
    lines(x,f_low,lwd=2,lty=2,col="blue")
    lines(x,f_upp,lwd=2,lty=2,col="blue")
  }
  
  tm=proc.time()-ptm
  return(list("time"=tm,"xi_sam"=xi_sam,"xi0_sam"=xi0_sam,"xi1_sam"=xi1_sam,"sig_sam"=sig_sam,
              "tau_sam"=tau_sam,"fhat_sam"=fhat_sam,"fmean"=fmean,"f_low"=f_low,"f_upp"=f_upp))
}


#END