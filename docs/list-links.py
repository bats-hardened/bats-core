import pickle  # nosec B403 - Sphinx stores its generated environment as pickle.
with open("build/doctrees/environment.pickle", "rb") as f:
    dat = pickle.load(f)  # nosec B301 - Read only the local Sphinx build output.
print(dat.domaindata['std']['labels'])
